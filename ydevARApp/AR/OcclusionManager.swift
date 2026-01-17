//
//  OcclusionManager.swift
//  ydevARApp
//
//  オクルージョン管理クラス - 現実世界による仮想オブジェクトの遮蔽
//
//  解説ポイント:
//  - People Occlusion: 人物による遮蔽（A12以降のデバイス）
//  - Scene Reconstruction: LiDARによるシーンメッシュ遮蔽
//  - OcclusionMaterial: 遮蔽用のマテリアル
//

import Foundation
import ARKit
import RealityKit
import Combine

/// オクルージョンを管理するクラス
@MainActor
class OcclusionManager: ObservableObject {

    // MARK: - Published Properties

    /// 人物オクルージョンが有効かどうか
    @Published var isPeopleOcclusionEnabled: Bool = false

    /// シーンオクルージョンが有効かどうか（LiDAR必須）
    @Published var isSceneOcclusionEnabled: Bool = false

    /// LiDARが利用可能かどうか
    @Published var isLiDARAvailable: Bool = false

    /// 人物オクルージョンが利用可能かどうか
    @Published var isPeopleOcclusionAvailable: Bool = false

    // MARK: - Internal Properties

    /// オクルージョンメッシュのアンカーID
    private var meshAnchorIds: Set<UUID> = []

    // MARK: - Initialization

    init() {
        checkDeviceCapabilities()
    }

    // MARK: - Device Capabilities

    /// デバイスの機能を確認
    private func checkDeviceCapabilities() {
        // LiDAR確認
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

        // 人物オクルージョン確認
        isPeopleOcclusionAvailable = ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)

        print("LiDAR利用可能: \(isLiDARAvailable)")
        print("人物オクルージョン利用可能: \(isPeopleOcclusionAvailable)")
    }

    // MARK: - Configuration

    /// オクルージョン設定をARConfigurationに適用
    func configureOcclusion(in configuration: ARWorldTrackingConfiguration) {
        // 人物オクルージョン
        if isPeopleOcclusionAvailable {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
            isPeopleOcclusionEnabled = true
            print("人物オクルージョン有効化")
        }

        // シーン再構築（LiDAR）によるオクルージョン
        if isLiDARAvailable {
            configuration.sceneReconstruction = .meshWithClassification
            isSceneOcclusionEnabled = true
            print("シーンオクルージョン有効化（LiDAR）")
        }
    }

    /// ARViewにオクルージョンを設定
    func setupOcclusion(in arView: ARView) {
        // 環境オクルージョンを有効化
        arView.environment.sceneUnderstanding.options.insert(.occlusion)

        // シーンメッシュの受信を有効化（LiDAR）
        if isLiDARAvailable {
            arView.environment.sceneUnderstanding.options.insert(.receivesLighting)
        }

        print("ARViewオクルージョン設定完了")
    }

    // MARK: - Scene Mesh Handling

    /// シーンメッシュアンカーを処理（LiDAR用）
    func handleMeshAnchor(_ anchor: ARMeshAnchor, in arView: ARView) {
        // 既に処理済みの場合はスキップ
        guard !meshAnchorIds.contains(anchor.identifier) else { return }
        meshAnchorIds.insert(anchor.identifier)

        // RealityKitのシーン理解機能が自動的にオクルージョンを処理するため
        // 追加のエンティティ生成は不要
        print("メッシュアンカー追加: \(anchor.identifier)")
    }

    /// シーンメッシュアンカーを更新
    func updateMeshAnchor(_ anchor: ARMeshAnchor) {
        // RealityKitが自動的に更新を処理
    }

    /// シーンメッシュアンカーを削除
    func removeMeshAnchor(_ anchor: ARMeshAnchor) {
        meshAnchorIds.remove(anchor.identifier)
    }

    // MARK: - Reset

    func reset() {
        meshAnchorIds.removeAll()
    }
}
