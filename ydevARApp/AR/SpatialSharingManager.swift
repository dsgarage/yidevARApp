//
//  SpatialSharingManager.swift
//  ydevARApp
//
//  空間共有クラス - Collaborative Sessionによるリアルタイム空間同期
//
//  解説ポイント:
//  - isCollaborationEnabled: 協調セッションを有効化するフラグ
//  - CollaborationData: デバイス間で共有される空間情報
//  - priority: critical（必須）とoptional（最適化用）の2種類
//

import Foundation
import ARKit
import Combine

/// 空間共有を管理するクラス
@MainActor
class SpatialSharingManager: ObservableObject {

    // MARK: - Published Properties

    /// 空間共有が有効かどうか
    @Published var isSharingEnabled: Bool = false

    /// 共有が確立されたかどうか
    @Published var isCollaborationEstablished: Bool = false

    /// 送信済みデータ量（バイト）
    @Published var dataSentBytes: Int = 0

    /// 受信済みデータ量（バイト）
    @Published var dataReceivedBytes: Int = 0

    // MARK: - Internal Properties

    /// 協調データの送信コールバック
    var onCollaborationDataReady: ((Data) -> Void)?

    /// ARセッションへの参照
    weak var session: ARSession?

    // MARK: - Configuration

    /// 協調セッションを設定に適用
    /// - Parameter configuration: ARWorldTrackingConfiguration
    ///
    /// 解説:
    /// isCollaborationEnabled = true にすると:
    /// - ARSessionDelegateのsession(_:didOutputCollaborationData:)が呼ばれる
    /// - 他デバイスからの協調データを適用可能になる
    /// - 同じ物理空間にいるデバイス間で座標系が自動的に一致する
    func enableCollaboration(in configuration: ARWorldTrackingConfiguration) {
        configuration.isCollaborationEnabled = true
        isSharingEnabled = true
    }

    /// 協調セッションを無効化
    func disableCollaboration() {
        isSharingEnabled = false
        isCollaborationEstablished = false
    }

    // MARK: - Collaboration Data Handling

    /// 協調データを処理して送信用Dataに変換
    /// - Parameter collaborationData: ARSessionから受け取った協調データ
    /// - Returns: 送信用にシリアライズされたData
    ///
    /// 解説:
    /// CollaborationData.priority:
    /// - .critical: 空間認識に必須のデータ（必ず送信すべき）
    /// - .optional: 最適化用データ（帯域幅に余裕があれば送信）
    nonisolated func handleCollaborationData(_ collaborationData: ARSession.CollaborationData) -> Data? {
        do {
            // NSKeyedArchiverでシリアライズ
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: collaborationData,
                requiringSecureCoding: true
            )

            // 送信量を記録（MainActorで更新）
            Task { @MainActor in
                self.dataSentBytes += data.count
            }

            // 優先度をログ出力
            let priority = collaborationData.priority == .critical ? "critical" : "optional"
            print("協調データを送信: \(data.count) bytes (\(priority))")

            return data
        } catch {
            print("協調データのシリアライズに失敗: \(error)")
            return nil
        }
    }

    /// 受信した協調データをセッションに適用
    /// - Parameters:
    ///   - data: 受信したData
    ///   - session: ARセッション
    ///
    /// 解説:
    /// - 受信したデータをデシリアライズ
    /// - session.update(with:)で協調データを適用
    /// - これにより他デバイスの空間認識情報がマージされる
    nonisolated func applyCollaborationData(_ data: Data, to session: ARSession) {
        do {
            guard let collaborationData = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: ARSession.CollaborationData.self,
                from: data
            ) else {
                print("協調データのデシリアライズに失敗")
                return
            }

            // 協調データをセッションに適用
            session.update(with: collaborationData)

            // 受信量を記録（MainActorで更新）
            Task { @MainActor in
                self.dataReceivedBytes += data.count
                self.isCollaborationEstablished = true
            }

            print("協調データを適用: \(data.count) bytes")
        } catch {
            print("協調データの適用に失敗: \(error)")
        }
    }

    // MARK: - Collaboration Status

    /// 協調が確立されているか確認
    /// - Parameter frame: ARFrame
    /// - Returns: 協調が確立されているかどうか
    ///
    /// 解説:
    /// 複数デバイスが同じ空間を認識している場合、
    /// 共有アンカーが存在するようになる
    func checkCollaborationStatus(from frame: ARFrame) -> Bool {
        // 協調が確立されると、他のデバイスからのアンカーが追加される
        // ここでは単純にデータ受信があれば確立とみなす
        return isCollaborationEstablished
    }

    // MARK: - Statistics

    /// 送受信統計をリセット
    func resetStatistics() {
        dataSentBytes = 0
        dataReceivedBytes = 0
    }

    /// 送受信統計を取得
    func getStatistics() -> (sent: Int, received: Int) {
        return (dataSentBytes, dataReceivedBytes)
    }

    // MARK: - Reset

    /// 空間共有をリセット
    func reset() {
        isSharingEnabled = false
        isCollaborationEstablished = false
        resetStatistics()
    }
}

// MARK: - Collaboration Data Priority Extension

extension ARSession.CollaborationData.Priority: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .critical:
            return "重要（必須）"
        case .optional:
            return "オプション（最適化用）"
        @unknown default:
            return "不明"
        }
    }
}
