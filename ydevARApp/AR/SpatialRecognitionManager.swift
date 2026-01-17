//
//  SpatialRecognitionManager.swift
//  ydevARApp
//
//  空間認識クラス - 空間マッピングとワールドマップ管理
//
//  解説ポイント:
//  - WorldMappingStatus: 空間認識の4段階（notAvailable → limited → extending → mapped）
//  - ARWorldMap: 認識した空間情報をシリアライズ可能な形式で保持
//  - 空間の永続化: ワールドマップを保存して後から読み込み可能
//

import Foundation
import ARKit
import Combine

/// 空間マッピング状態
enum MappingQuality: String {
    case notAvailable = "準備中"
    case limited = "制限あり"
    case extending = "拡張中"
    case mapped = "マッピング完了"

    var color: String {
        switch self {
        case .notAvailable: return "red"
        case .limited: return "orange"
        case .extending: return "yellow"
        case .mapped: return "green"
        }
    }
}

/// 空間認識を管理するクラス
@MainActor
class SpatialRecognitionManager: ObservableObject {

    // MARK: - Published Properties

    /// 現在のマッピング状態
    @Published var mappingStatus: ARFrame.WorldMappingStatus = .notAvailable

    /// マッピング品質（UI表示用）
    @Published var mappingQuality: MappingQuality = .notAvailable

    /// ワールドマップが利用可能かどうか
    @Published var isWorldMapAvailable: Bool = false

    /// フィーチャーポイント（特徴点）の数
    @Published var featurePointCount: Int = 0

    // MARK: - Internal Properties

    /// 最後に取得したワールドマップ
    private var currentWorldMap: ARWorldMap?

    /// ARセッションへの参照
    weak var session: ARSession?

    // MARK: - Mapping Status

    /// フレームからマッピング状態を更新
    /// - Parameter frame: ARフレーム
    ///
    /// 解説:
    /// WorldMappingStatusは4段階:
    /// - .notAvailable: マッピング情報が不足
    /// - .limited: 限定的なマッピング（特徴点が少ない）
    /// - .extending: マッピング中（より多くの特徴点を収集中）
    /// - .mapped: 十分なマッピングが完了（ワールドマップの取得が可能）
    func updateMappingStatus(from frame: ARFrame) {
        mappingStatus = frame.worldMappingStatus
        mappingQuality = convertToQuality(frame.worldMappingStatus)
        isWorldMapAvailable = (frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending)

        // フィーチャーポイント数を更新
        if let points = frame.rawFeaturePoints?.points {
            featurePointCount = points.count
        }
    }

    /// ARFrame.WorldMappingStatusをMappingQualityに変換
    private func convertToQuality(_ status: ARFrame.WorldMappingStatus) -> MappingQuality {
        switch status {
        case .notAvailable:
            return .notAvailable
        case .limited:
            return .limited
        case .extending:
            return .extending
        case .mapped:
            return .mapped
        @unknown default:
            return .notAvailable
        }
    }

    // MARK: - World Map Management

    /// 現在のワールドマップを取得
    /// - Returns: ARWorldMap
    /// - Throws: ワールドマップ取得エラー
    ///
    /// 解説:
    /// - ワールドマップには認識した空間の特徴点、アンカー情報が含まれる
    /// - mappingStatusが.mappedまたは.extendingの時に取得可能
    /// - 取得したマップは他デバイスと共有したり、後で再利用可能
    func getCurrentWorldMap() async throws -> ARWorldMap {
        guard let session = session else {
            throw SpatialRecognitionError.sessionNotAvailable
        }

        guard isWorldMapAvailable else {
            throw SpatialRecognitionError.mappingNotComplete
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.getCurrentWorldMap { [weak self] worldMap, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let worldMap = worldMap else {
                    continuation.resume(throwing: SpatialRecognitionError.worldMapNotAvailable)
                    return
                }

                Task { @MainActor in
                    self?.currentWorldMap = worldMap
                }
                continuation.resume(returning: worldMap)
            }
        }
    }

    /// ワールドマップをセッションに読み込み
    /// - Parameters:
    ///   - worldMap: 読み込むワールドマップ
    ///   - session: ARセッション
    ///
    /// 解説:
    /// - 他デバイスから受信したワールドマップを適用
    /// - 同じ物理空間にいれば、座標系が一致する
    nonisolated func loadWorldMap(_ worldMap: ARWorldMap, to session: ARSession) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.initialWorldMap = worldMap

        // 協調セッションを有効化
        configuration.isCollaborationEnabled = true

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    /// ワールドマップをDataにシリアライズ
    /// - Parameter worldMap: ワールドマップ
    /// - Returns: シリアライズされたData
    nonisolated func serializeWorldMap(_ worldMap: ARWorldMap) throws -> Data {
        return try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
    }

    /// DataからワールドマップをデシリアライズSet
    /// - Parameter data: シリアライズされたData
    /// - Returns: ARWorldMap
    nonisolated func deserializeWorldMap(from data: Data) throws -> ARWorldMap {
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            throw SpatialRecognitionError.deserializationFailed
        }
        return worldMap
    }

    // MARK: - Persistence

    /// ワールドマップをファイルに保存
    /// - Parameter filename: ファイル名
    func saveWorldMap(filename: String) async throws {
        let worldMap = try await getCurrentWorldMap()
        let data = try serializeWorldMap(worldMap)

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("\(filename).armap")

        try data.write(to: fileURL)
        print("ワールドマップを保存: \(fileURL.path)")
    }

    /// ファイルからワールドマップを読み込み
    /// - Parameter filename: ファイル名
    /// - Returns: ARWorldMap
    nonisolated func loadWorldMap(filename: String) throws -> ARWorldMap {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDirectory.appendingPathComponent("\(filename).armap")

        let data = try Data(contentsOf: fileURL)
        return try deserializeWorldMap(from: data)
    }

    // MARK: - Reset

    /// 空間認識をリセット
    func reset() {
        mappingStatus = .notAvailable
        mappingQuality = .notAvailable
        isWorldMapAvailable = false
        featurePointCount = 0
        currentWorldMap = nil
    }
}

// MARK: - Errors

enum SpatialRecognitionError: LocalizedError {
    case sessionNotAvailable
    case mappingNotComplete
    case worldMapNotAvailable
    case deserializationFailed

    var errorDescription: String? {
        switch self {
        case .sessionNotAvailable:
            return "ARセッションが利用できません"
        case .mappingNotComplete:
            return "空間マッピングが完了していません"
        case .worldMapNotAvailable:
            return "ワールドマップを取得できません"
        case .deserializationFailed:
            return "ワールドマップのデシリアライズに失敗しました"
        }
    }
}
