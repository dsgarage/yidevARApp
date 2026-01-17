//
//  PlaneDetectionManager.swift
//  ydevARApp
//
//  平面検知クラス - ARKitによる水平面・垂直面の検出と可視化
//
//  解説ポイント:
//  - ARPlaneAnchor: 検出された平面を表すアンカー
//  - classification: 床、壁、テーブル、天井などの分類
//  - extent: 平面の大きさ（幅と高さ）
//  - center: 平面の中心位置（アンカーのローカル座標系）
//

import Foundation
import ARKit
import RealityKit
import Combine

/// 平面検知を管理するクラス
@MainActor
class PlaneDetectionManager: ObservableObject {

    // MARK: - Published Properties

    /// 検出された平面アンカーのリスト
    @Published var detectedPlanes: [UUID: ARPlaneAnchor] = [:]

    /// 平面検出が有効かどうか
    @Published var isDetectionEnabled: Bool = true

    /// 検出された水平面の数
    @Published var horizontalPlaneCount: Int = 0

    /// 検出された垂直面の数
    @Published var verticalPlaneCount: Int = 0

    // MARK: - Internal Properties

    /// 平面の可視化用エンティティを管理
    private var planeEntities: [UUID: ModelEntity] = [:]

    /// 平面表示の透明度（見やすい半透明）
    private let planeOpacity: Float = 0.5

    /// 最後の更新時刻（スロットリング用）
    private var lastUpdateTime: [UUID: Date] = [:]

    /// 更新の最小間隔（秒）- ちらつき軽減
    private let updateThrottleInterval: TimeInterval = 0.5

    /// 前回のサイズ（大きな変化のみ更新）
    private var lastPlaneSize: [UUID: (width: Float, height: Float)] = [:]

    /// サイズ変化の閾値（これ以上変化したら更新）
    private let sizeChangeThreshold: Float = 0.1

    /// 表示する平面の最小サイズ（これより小さい平面は非表示）
    private let minPlaneSize: Float = 0.3

    /// 表示する平面の最大数
    private let maxDisplayedPlanes: Int = 5

    /// 高さの統合閾値（この範囲内の平面は同一とみなす）
    private let heightMergeThreshold: Float = 0.1

    // MARK: - Configuration

    /// 平面検出の設定を作成
    func configurePlaneDetection() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()

        // 水平面のみ検出（垂直面を減らしてパフォーマンス向上）
        configuration.planeDetection = [.horizontal]

        // 環境テクスチャを無効化（パフォーマンス向上）
        configuration.environmentTexturing = .none

        // シーン再構築を無効化（パフォーマンス向上）
        // LiDARデバイスでもメッシュ生成を行わない
        configuration.sceneReconstruction = []

        return configuration
    }

    // MARK: - Anchor Handling

    /// 新しいアンカーが追加された時の処理
    func didAdd(anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

        detectedPlanes[planeAnchor.identifier] = planeAnchor
        lastUpdateTime[planeAnchor.identifier] = Date()
        lastPlaneSize[planeAnchor.identifier] = (planeAnchor.planeExtent.width, planeAnchor.planeExtent.height)
        updatePlaneCounts()

        print("平面検出: \(classificationName(for: planeAnchor.classification))")
    }

    /// アンカーが更新された時の処理（スロットリング付き）
    func didUpdate(anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

        detectedPlanes[planeAnchor.identifier] = planeAnchor
    }

    /// 平面の可視化を更新すべきかチェック
    func shouldUpdateVisualization(for anchor: ARPlaneAnchor) -> Bool {
        let now = Date()

        // 時間ベースのスロットリング
        if let lastTime = lastUpdateTime[anchor.identifier],
           now.timeIntervalSince(lastTime) < updateThrottleInterval {
            return false
        }

        // サイズ変化のチェック
        if let lastSize = lastPlaneSize[anchor.identifier] {
            let widthChange = abs(anchor.planeExtent.width - lastSize.width)
            let heightChange = abs(anchor.planeExtent.height - lastSize.height)

            if widthChange < sizeChangeThreshold && heightChange < sizeChangeThreshold {
                return false
            }
        }

        // 更新を許可
        lastUpdateTime[anchor.identifier] = now
        lastPlaneSize[anchor.identifier] = (anchor.planeExtent.width, anchor.planeExtent.height)
        return true
    }

    /// アンカーが削除された時の処理
    func didRemove(anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

        detectedPlanes.removeValue(forKey: planeAnchor.identifier)
        planeEntities.removeValue(forKey: planeAnchor.identifier)
        lastUpdateTime.removeValue(forKey: planeAnchor.identifier)
        lastPlaneSize.removeValue(forKey: planeAnchor.identifier)
        updatePlaneCounts()
    }

    // MARK: - Visualization

    /// 平面の可視化用エンティティを作成（半透明・影なし）
    func createPlaneVisualization(for anchor: ARPlaneAnchor) -> ModelEntity {
        let width = anchor.planeExtent.width
        let height = anchor.planeExtent.height

        // 平面メッシュを生成
        let mesh = MeshResource.generatePlane(width: width, depth: height)

        // 半透明マテリアル（SimpleMaterialで影なし）
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor.systemBlue.withAlphaComponent(CGFloat(planeOpacity)))
        material.metallic = 0
        material.roughness = 1

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = [anchor.center.x, 0, anchor.center.z]

        planeEntities[anchor.identifier] = entity

        return entity
    }

    /// 既存の平面エンティティを更新（スロットリング付き）
    func updatePlaneVisualization(_ entity: ModelEntity, for anchor: ARPlaneAnchor) {
        // スロットリングチェック
        guard shouldUpdateVisualization(for: anchor) else { return }

        let width = anchor.planeExtent.width
        let height = anchor.planeExtent.height

        // メッシュを再生成
        let mesh = MeshResource.generatePlane(width: width, depth: height)
        entity.model?.mesh = mesh
        entity.position = [anchor.center.x, 0, anchor.center.z]
    }

    // MARK: - Helper Methods

    private func updatePlaneCounts() {
        horizontalPlaneCount = detectedPlanes.values.filter { $0.alignment == .horizontal }.count
        verticalPlaneCount = detectedPlanes.values.filter { $0.alignment == .vertical }.count
    }

    private func classificationName(for classification: ARPlaneAnchor.Classification) -> String {
        switch classification {
        case .floor: return "床"
        case .ceiling: return "天井"
        case .wall: return "壁"
        case .table: return "テーブル"
        case .seat: return "座席"
        case .door: return "ドア"
        case .window: return "窓"
        default: return "不明"
        }
    }

    func nearestPlane(to position: SIMD3<Float>) -> ARPlaneAnchor? {
        var nearestPlane: ARPlaneAnchor?
        var minDistance: Float = .infinity

        for plane in detectedPlanes.values {
            let planePosition = SIMD3<Float>(plane.transform.columns.3.x,
                                              plane.transform.columns.3.y,
                                              plane.transform.columns.3.z)
            let distance = simd_distance(position, planePosition)

            if distance < minDistance {
                minDistance = distance
                nearestPlane = plane
            }
        }

        return nearestPlane
    }

    func getAllPlaneEntities() -> [UUID: ModelEntity] {
        return planeEntities
    }

    /// 平面可視化の表示/非表示を切り替え
    func setVisualizationVisible(_ visible: Bool) {
        for entity in planeEntities.values {
            entity.isEnabled = visible
        }
    }

    // MARK: - Plane Optimization

    /// 平面を最適化（小さいものを非表示、大きいものを優先表示）
    func optimizePlaneDisplay() {
        // 平面をサイズ順にソート
        let sortedPlanes = detectedPlanes.values.sorted { plane1, plane2 in
            let size1 = plane1.planeExtent.width * plane1.planeExtent.height
            let size2 = plane2.planeExtent.width * plane2.planeExtent.height
            return size1 > size2
        }

        // 表示する平面を決定
        var displayedCount = 0
        var displayedHeights: [Float] = []

        for plane in sortedPlanes {
            let planeSize = plane.planeExtent.width * plane.planeExtent.height
            let planeHeight = plane.transform.columns.3.y

            // 最小サイズチェック
            guard planeSize >= minPlaneSize * minPlaneSize else {
                planeEntities[plane.identifier]?.isEnabled = false
                continue
            }

            // 同じ高さの平面が既に表示されているかチェック
            let isSameHeight = displayedHeights.contains { abs($0 - planeHeight) < heightMergeThreshold }

            if isSameHeight {
                // 同じ高さの平面は非表示（統合効果）
                planeEntities[plane.identifier]?.isEnabled = false
            } else if displayedCount < maxDisplayedPlanes {
                // 表示
                planeEntities[plane.identifier]?.isEnabled = true
                displayedHeights.append(planeHeight)
                displayedCount += 1
            } else {
                // 最大数を超えたら非表示
                planeEntities[plane.identifier]?.isEnabled = false
            }
        }
    }

    /// 平面を追加時に最適化を実行すべきか判定
    func shouldOptimize() -> Bool {
        return detectedPlanes.count > maxDisplayedPlanes
    }

    func reset() {
        detectedPlanes.removeAll()
        planeEntities.removeAll()
        lastUpdateTime.removeAll()
        lastPlaneSize.removeAll()
        horizontalPlaneCount = 0
        verticalPlaneCount = 0
    }
}
