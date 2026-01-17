//
//  AvatarManager.swift
//  ydevARApp
//
//  参加者アバター管理クラス - 他の参加者の位置を簡易アバターで表示
//
//  解説ポイント:
//  - カメラ位置から参加者の位置を取得
//  - 簡易アバター（球体）の生成
//  - 位置情報のリアルタイム同期（約10Hz）
//

import Foundation
import RealityKit
import ARKit
import SwiftUI
import Combine

/// 参加者アバターを管理するクラス
@MainActor
class AvatarManager: ObservableObject {

    // MARK: - Published Properties

    /// 参加者情報の辞書（ID -> ParticipantInfo）
    @Published var participants: [String: ParticipantInfo] = [:]

    /// 自分の参加者ID
    @Published var myParticipantId: String

    /// 自分の表示名
    @Published var myDisplayName: String

    // MARK: - Internal Properties

    /// アバターエンティティの辞書（参加者ID -> Entity）
    private var avatarEntities: [String: Entity] = [:]

    /// 位置送信用のタイマー
    private var positionBroadcastTimer: Timer?

    /// 位置送信の間隔（秒）- 約10Hz
    private let broadcastInterval: TimeInterval = 0.1

    /// アバターの半径
    private let avatarRadius: Float = 0.08

    /// 名前ラベルのフォントサイズ
    private let nameLabelFontSize: CGFloat = 0.04

    /// 位置送信コールバック
    var onPositionBroadcast: ((ParticipantPositionUpdate) -> Void)?

    // MARK: - Initialization

    init() {
        self.myParticipantId = UUID().uuidString
        self.myDisplayName = UIDevice.current.name
    }

    // MARK: - Position Broadcasting

    /// 自分の位置を送信開始
    /// - Parameter arView: ARView（カメラ位置取得用）
    func startBroadcastingPosition(arView: ARView) {
        stopBroadcastingPosition()

        positionBroadcastTimer = Timer.scheduledTimer(withTimeInterval: broadcastInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard let cameraTransform = arView.session.currentFrame?.camera.transform else { return }
                self.broadcastMyPosition(cameraTransform: cameraTransform)
            }
        }
    }

    /// 位置送信を停止
    func stopBroadcastingPosition() {
        positionBroadcastTimer?.invalidate()
        positionBroadcastTimer = nil
    }

    /// 自分の位置を送信
    /// - Parameter cameraTransform: カメラのトランスフォーム
    ///
    /// 解説:
    /// - カメラのトランスフォームから位置を抽出
    /// - columns.3には位置情報（x, y, z, w）が格納されている
    func broadcastMyPosition(cameraTransform: simd_float4x4) {
        let position = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        let update = ParticipantPositionUpdate(
            participantId: myParticipantId,
            position: position,
            timestamp: Date()
        )

        onPositionBroadcast?(update)
    }

    // MARK: - Participant Management

    /// 参加者を追加
    /// - Parameter participant: 参加者情報
    func addParticipant(_ participant: ParticipantInfo) {
        guard participant.id != myParticipantId else { return }
        participants[participant.id] = participant
    }

    /// 参加者の位置を更新
    /// - Parameters:
    ///   - id: 参加者ID
    ///   - position: 新しい位置
    func updateParticipant(id: String, position: SIMD3<Float>) {
        guard id != myParticipantId else { return }

        if var participant = participants[id] {
            participant.position = position
            participant.lastUpdated = Date()
            participants[id] = participant

            // アバターエンティティの位置も更新
            if let entity = avatarEntities[id] {
                entity.position = position
            }
        }
    }

    /// 参加者を削除
    /// - Parameter id: 参加者ID
    func removeParticipant(id: String) {
        participants.removeValue(forKey: id)

        // アバターエンティティも削除
        if let entity = avatarEntities[id] {
            entity.removeFromParent()
            avatarEntities.removeValue(forKey: id)
        }
    }

    // MARK: - Avatar Entity Creation

    /// 参加者用のアバターエンティティを作成
    /// - Parameter participant: 参加者情報
    /// - Returns: アバターEntity（球体 + 名前ラベル）
    ///
    /// 解説:
    /// - MeshResource.generateSphere: 球体メッシュを生成
    /// - 参加者ごとに異なる色を使用
    /// - 名前ラベルは別のエンティティとして追加
    func createAvatarEntity(for participant: ParticipantInfo) -> Entity {
        let avatarEntity = Entity()

        // 球体メッシュを作成
        let sphereMesh = MeshResource.generateSphere(radius: avatarRadius)

        // 参加者の色でマテリアルを作成
        var material = SimpleMaterial()
        let uiColor = UIColor(participant.color)
        material.color = .init(tint: uiColor)
        material.roughness = 0.3
        material.metallic = 0.1

        // 球体モデルを作成
        let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [material])
        avatarEntity.addChild(sphereEntity)

        // 名前ラベルを作成（球体の上に配置）
        let labelEntity = createNameLabel(name: participant.displayName, color: participant.color)
        labelEntity.position = [0, avatarRadius + 0.05, 0]  // 頭の上に配置
        avatarEntity.addChild(labelEntity)

        // 初期位置を設定
        avatarEntity.position = participant.position

        // エンティティを辞書に保存
        avatarEntities[participant.id] = avatarEntity

        return avatarEntity
    }

    /// 名前ラベルエンティティを作成
    /// - Parameters:
    ///   - name: 表示名
    ///   - color: ラベルの色
    /// - Returns: ラベルEntity
    private func createNameLabel(name: String, color: Color) -> Entity {
        let labelEntity = Entity()

        // テキストメッシュを生成（大きめのフォント）
        let textMesh = MeshResource.generateText(
            name,
            extrusionDepth: 0.002,
            font: .boldSystemFont(ofSize: nameLabelFontSize),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )

        // 白い文字で視認性を高める
        var material = SimpleMaterial()
        material.color = .init(tint: .white)
        material.roughness = 1.0

        let textEntity = ModelEntity(mesh: textMesh, materials: [material])

        // テキストを中央揃えに調整
        let bounds = textEntity.visualBounds(relativeTo: nil)
        textEntity.position.x = -bounds.center.x

        // ビルボード効果（常にカメラに向く）を追加
        labelEntity.addChild(textEntity)

        return labelEntity
    }

    /// 参加者のアバターエンティティを取得
    /// - Parameter id: 参加者ID
    /// - Returns: アバターEntity（存在しない場合はnil）
    func getAvatarEntity(for id: String) -> Entity? {
        return avatarEntities[id]
    }

    /// すべてのアバターエンティティを取得
    func getAllAvatarEntities() -> [String: Entity] {
        return avatarEntities
    }

    // MARK: - Cleanup

    /// 古い参加者を削除（タイムアウト処理）
    /// - Parameter timeout: タイムアウト時間（秒）
    func removeStaleParticipants(timeout: TimeInterval = 10.0) {
        let now = Date()
        let staleIds = participants.filter { now.timeIntervalSince($0.value.lastUpdated) > timeout }.map { $0.key }

        for id in staleIds {
            removeParticipant(id: id)
        }
    }

    /// すべてをリセット
    func reset() {
        stopBroadcastingPosition()

        for entity in avatarEntities.values {
            entity.removeFromParent()
        }

        avatarEntities.removeAll()
        participants.removeAll()
    }
}
