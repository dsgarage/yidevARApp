//
//  ObjectDetectionManager.swift
//  ydevARApp
//
//  オブジェクト検知クラス - 現実世界の物体を検出・分類
//
//  解説ポイント:
//  - ARMeshClassification: LiDARによるメッシュ分類
//  - ARPlaneAnchor.Classification: 平面の分類（床、壁、テーブル等）
//  - シーン理解による物体認識
//

import Foundation
import ARKit
import RealityKit
import Combine

/// 検出されたオブジェクトの情報
struct DetectedObject: Identifiable, Equatable {
    let id: UUID
    let classification: ObjectClassification
    var position: SIMD3<Float>
    var bounds: SIMD3<Float>  // 幅、高さ、奥行き
    let detectedAt: Date

    static func == (lhs: DetectedObject, rhs: DetectedObject) -> Bool {
        lhs.id == rhs.id
    }
}

/// オブジェクトの分類
enum ObjectClassification: String, CaseIterable {
    case floor = "床"
    case wall = "壁"
    case ceiling = "天井"
    case table = "テーブル"
    case seat = "座席"
    case door = "ドア"
    case window = "窓"
    case unknown = "不明"

    /// ARPlaneAnchor.Classificationから変換
    init(from arClassification: ARPlaneAnchor.Classification) {
        switch arClassification {
        case .floor: self = .floor
        case .wall: self = .wall
        case .ceiling: self = .ceiling
        case .table: self = .table
        case .seat: self = .seat
        case .door: self = .door
        case .window: self = .window
        default: self = .unknown
        }
    }

    /// ARMeshClassificationから変換
    init(from meshClassification: ARMeshClassification) {
        switch meshClassification {
        case .floor: self = .floor
        case .wall: self = .wall
        case .ceiling: self = .ceiling
        case .table: self = .table
        case .seat: self = .seat
        case .door: self = .door
        case .window: self = .window
        default: self = .unknown
        }
    }

    /// 表示色
    var color: UIColor {
        switch self {
        case .floor: return .systemGreen
        case .wall: return .systemBlue
        case .ceiling: return .systemGray
        case .table: return .systemOrange
        case .seat: return .systemPurple
        case .door: return .systemBrown
        case .window: return .systemCyan
        case .unknown: return .systemGray
        }
    }

    /// SF Symbols アイコン名
    var symbolName: String {
        switch self {
        case .floor: return "square.grid.2x2"
        case .wall: return "rectangle.portrait"
        case .ceiling: return "square.tophalf.filled"
        case .table: return "tablecells"
        case .seat: return "chair.fill"
        case .door: return "door.left.hand.open"
        case .window: return "window.horizontal"
        case .unknown: return "questionmark.square"
        }
    }
}

/// オブジェクト検知を管理するクラス
@MainActor
class ObjectDetectionManager: ObservableObject {

    // MARK: - Published Properties

    /// 検出されたオブジェクトのリスト
    @Published var detectedObjects: [UUID: DetectedObject] = [:]

    /// 検出が有効かどうか
    @Published var isDetectionEnabled: Bool = true

    /// 分類ごとのカウント
    @Published var classificationCounts: [ObjectClassification: Int] = [:]

    // MARK: - Internal Properties

    /// 可視化用エンティティ
    private var visualizationEntities: [UUID: ModelEntity] = [:]

    /// 可視化の透明度（見やすい半透明）
    private let visualizationOpacity: Float = 0.5

    /// 最小検出サイズ（ノイズ除去）
    private let minDetectionSize: Float = 0.1

    // MARK: - Configuration

    /// オブジェクト検知の設定を作成
    func configureObjectDetection(in configuration: ARWorldTrackingConfiguration) {
        // 平面検出を全方向に設定（オブジェクト分類のため）
        configuration.planeDetection = [.horizontal, .vertical]

        // LiDARが利用可能な場合はメッシュ分類を有効化
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
            print("メッシュ分類有効化（LiDAR）")
        }
    }

    // MARK: - Plane Detection Handling

    /// 平面アンカーからオブジェクトを検出
    func detectFromPlane(_ anchor: ARPlaneAnchor) {
        guard isDetectionEnabled else { return }

        let classification = ObjectClassification(from: anchor.classification)

        // 不明なものは無視
        guard classification != .unknown else { return }

        let position = SIMD3<Float>(
            anchor.transform.columns.3.x,
            anchor.transform.columns.3.y,
            anchor.transform.columns.3.z
        )

        let bounds = SIMD3<Float>(
            anchor.planeExtent.width,
            0.01,
            anchor.planeExtent.height
        )

        // 小さすぎるものは無視
        guard bounds.x > minDetectionSize || bounds.z > minDetectionSize else { return }

        let detectedObject = DetectedObject(
            id: anchor.identifier,
            classification: classification,
            position: position,
            bounds: bounds,
            detectedAt: Date()
        )

        detectedObjects[anchor.identifier] = detectedObject
        updateClassificationCounts()

        print("オブジェクト検出: \(classification.rawValue) サイズ: \(bounds.x)m x \(bounds.z)m")
    }

    /// 平面アンカーの更新を処理
    func updateFromPlane(_ anchor: ARPlaneAnchor) {
        guard var existing = detectedObjects[anchor.identifier] else {
            detectFromPlane(anchor)
            return
        }

        existing.position = SIMD3<Float>(
            anchor.transform.columns.3.x,
            anchor.transform.columns.3.y,
            anchor.transform.columns.3.z
        )
        existing.bounds = SIMD3<Float>(
            anchor.planeExtent.width,
            0.01,
            anchor.planeExtent.height
        )

        detectedObjects[anchor.identifier] = existing
    }

    /// 平面アンカーの削除を処理
    func removeFromPlane(_ anchor: ARPlaneAnchor) {
        detectedObjects.removeValue(forKey: anchor.identifier)
        visualizationEntities.removeValue(forKey: anchor.identifier)?.removeFromParent()
        updateClassificationCounts()
    }

    // MARK: - Mesh Classification Handling (LiDAR)

    /// メッシュアンカーからオブジェクトを検出
    func detectFromMesh(_ anchor: ARMeshAnchor, in arView: ARView) {
        guard isDetectionEnabled else { return }

        let geometry = anchor.geometry

        // 分類情報がある場合のみ処理
        guard let classificationSource = geometry.classification else { return }

        // 各分類のフェース数をカウント
        var classificationFaces: [ARMeshClassification: Int] = [:]

        let faceCount = geometry.faces.count
        let classificationPointer = classificationSource.buffer.contents()
            .advanced(by: classificationSource.offset)
        let stride = classificationSource.stride

        for i in 0..<faceCount {
            let classValue = classificationPointer
                .advanced(by: stride * i)
                .assumingMemoryBound(to: UInt8.self)
                .pointee

            if let meshClass = ARMeshClassification(rawValue: Int(classValue)) {
                classificationFaces[meshClass, default: 0] += 1
            }
        }

        // 最も多い分類を採用
        if let dominantClass = classificationFaces.max(by: { $0.value < $1.value })?.key {
            let classification = ObjectClassification(from: dominantClass)

            if classification != .unknown {
                let position = SIMD3<Float>(
                    anchor.transform.columns.3.x,
                    anchor.transform.columns.3.y,
                    anchor.transform.columns.3.z
                )

                let detectedObject = DetectedObject(
                    id: anchor.identifier,
                    classification: classification,
                    position: position,
                    bounds: SIMD3<Float>(0.5, 0.5, 0.5),  // メッシュの場合は概算
                    detectedAt: Date()
                )

                detectedObjects[anchor.identifier] = detectedObject
                updateClassificationCounts()
            }
        }
    }

    // MARK: - Visualization

    /// 検出したオブジェクトを可視化
    func createVisualization(for object: DetectedObject) -> ModelEntity {
        let mesh = MeshResource.generateBox(
            width: object.bounds.x,
            height: max(object.bounds.y, 0.02),
            depth: object.bounds.z,
            cornerRadius: 0.01
        )

        // 半透明マテリアル（PhysicallyBasedMaterialで透過を実現）
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: object.classification.color.withAlphaComponent(CGFloat(visualizationOpacity)))
        material.blending = .transparent(opacity: .init(floatLiteral: visualizationOpacity))
        material.faceCulling = .none  // 両面表示

        let entity = ModelEntity(mesh: mesh, materials: [material])
        visualizationEntities[object.id] = entity

        return entity
    }

    // MARK: - Helper Methods

    private func updateClassificationCounts() {
        var counts: [ObjectClassification: Int] = [:]
        for object in detectedObjects.values {
            counts[object.classification, default: 0] += 1
        }
        classificationCounts = counts
    }

    /// 指定した位置に最も近いオブジェクトを取得
    func nearestObject(to position: SIMD3<Float>) -> DetectedObject? {
        var nearest: DetectedObject?
        var minDistance: Float = .infinity

        for object in detectedObjects.values {
            let distance = simd_distance(position, object.position)
            if distance < minDistance {
                minDistance = distance
                nearest = object
            }
        }

        return nearest
    }

    /// 指定した分類のオブジェクトを取得
    func objects(of classification: ObjectClassification) -> [DetectedObject] {
        return detectedObjects.values.filter { $0.classification == classification }
    }

    // MARK: - Reset

    func reset() {
        detectedObjects.removeAll()
        classificationCounts.removeAll()
        for entity in visualizationEntities.values {
            entity.removeFromParent()
        }
        visualizationEntities.removeAll()
    }
}
