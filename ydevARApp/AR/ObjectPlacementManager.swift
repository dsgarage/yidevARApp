//
//  ObjectPlacementManager.swift
//  ydevARApp
//
//  3Dオブジェクト配置クラス - 物理シミュレーションによる投げ入れ
//
//  解説ポイント:
//  - PhysicsBodyComponent: Rigidbody相当の物理ボディ
//  - PhysicsMotionComponent: 速度・角速度の設定
//  - CollisionComponent: 衝突判定
//

import Foundation
import RealityKit
import ARKit
import Combine

/// 3Dオブジェクトの配置を管理するクラス
@MainActor
class ObjectPlacementManager: ObservableObject {

    // MARK: - Published Properties

    /// 配置されたオブジェクトのリスト
    @Published var placedObjects: [SharedObject] = []

    /// 現在選択中のオブジェクトタイプ
    @Published var selectedObjectType: ObjectType = .cube

    /// 投げる強さ（1.0 ~ 3.0）
    @Published var throwStrength: Float = 2.0

    // MARK: - Internal Properties

    /// オブジェクトエンティティの辞書（オブジェクトID -> Entity）
    private var objectEntities: [UUID: Entity] = [:]

    /// 床面エンティティ（物理衝突用）
    private var floorEntities: [UUID: ModelEntity] = [:]

    /// 自動削除タイマーの辞書
    private var deletionTimers: [UUID: Task<Void, Never>] = [:]

    /// オブジェクトの自動削除時間（秒）
    private let autoDeleteInterval: TimeInterval = 5.0

    /// 最大オブジェクト数（パフォーマンス用）
    private let maxObjectCount: Int = 20

    /// 物理シミュレーションを有効にする最大距離
    private let maxPhysicsDistance: Float = 5.0

    /// 配置者のID（自分）
    var placerId: String = ""

    /// オブジェクト配置コールバック
    var onObjectPlaced: ((SharedObject) -> Void)?

    /// ARViewへの参照
    weak var arView: ARView?

    // MARK: - Physics Throwing

    /// タップ位置に向かってオブジェクトを投げる
    /// - Parameters:
    ///   - screenPoint: タップしたスクリーン座標
    ///   - arView: ARView
    func throwObjectToward(screenPoint: CGPoint, in arView: ARView) {
        guard let frame = arView.session.currentFrame else {
            print("ARフレームが取得できません")
            return
        }

        // カメラの位置と向きを取得
        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        // タップ位置からレイの方向を計算
        let throwDirection = calculateThrowDirection(
            screenPoint: screenPoint,
            cameraTransform: cameraTransform,
            viewSize: arView.bounds.size
        )

        // オブジェクトの初期位置（カメラの少し前）
        let spawnOffset: Float = 0.3
        let spawnPosition = cameraPosition + throwDirection * spawnOffset

        // SharedObjectを作成
        let sharedObject = SharedObject(
            type: selectedObjectType,
            position: spawnPosition,
            placedBy: placerId,
            colorRGB: randomObjectColor()
        )

        // 物理エンティティを作成
        let entity = createPhysicsEntity(for: sharedObject)
        entity.position = spawnPosition

        // シーンに追加
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        // 初速を設定（投げる）
        let throwSpeed: Float = 3.0 * throwStrength
        let velocity = throwDirection * throwSpeed

        // ランダムな回転を追加
        let angularVelocity = SIMD3<Float>(
            Float.random(in: -5...5),
            Float.random(in: -5...5),
            Float.random(in: -5...5)
        )

        // PhysicsMotionComponentで速度を設定
        entity.components.set(PhysicsMotionComponent(
            linearVelocity: velocity,
            angularVelocity: angularVelocity
        ))

        // オブジェクトを記録
        placedObjects.append(sharedObject)
        objectEntities[sharedObject.id] = entity

        // 5秒後に自動削除
        scheduleAutoDelete(for: sharedObject.id)

        // 最大数を超えたら古いものから削除
        enforceMaxObjectCount()

        // コールバック
        onObjectPlaced?(sharedObject)

        print("投げ入れ: \(selectedObjectType.rawValue) 速度: \(velocity)")
    }

    /// スクリーン座標から投げる方向を計算
    private func calculateThrowDirection(
        screenPoint: CGPoint,
        cameraTransform: simd_float4x4,
        viewSize: CGSize
    ) -> SIMD3<Float> {
        // スクリーン座標を正規化（-1 ~ 1）
        let normalizedX = Float((screenPoint.x / viewSize.width) * 2 - 1)
        let normalizedY = Float((1 - screenPoint.y / viewSize.height) * 2 - 1)

        // カメラの前方向、右方向、上方向を取得
        let forward = -SIMD3<Float>(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        )
        let right = SIMD3<Float>(
            cameraTransform.columns.0.x,
            cameraTransform.columns.0.y,
            cameraTransform.columns.0.z
        )
        let up = SIMD3<Float>(
            cameraTransform.columns.1.x,
            cameraTransform.columns.1.y,
            cameraTransform.columns.1.z
        )

        // FOVに基づいてオフセットを計算（おおよそ60度のFOV）
        let fovFactor: Float = 0.6
        let direction = forward + right * normalizedX * fovFactor + up * normalizedY * fovFactor

        return simd_normalize(direction)
    }

    // MARK: - Physics Entity Creation

    /// 物理シミュレーション対応のエンティティを作成
    func createPhysicsEntity(for sharedObject: SharedObject) -> ModelEntity {
        let mesh: MeshResource
        let size = sharedObject.type.defaultSize
        var collisionShape: ShapeResource

        switch sharedObject.type {
        case .cube:
            mesh = MeshResource.generateBox(size: size, cornerRadius: 0.002)
            collisionShape = ShapeResource.generateBox(size: [size, size, size])
        case .sphere:
            mesh = MeshResource.generateSphere(radius: size)
            collisionShape = ShapeResource.generateSphere(radius: size)
        case .cylinder:
            // 縦長の箱で代用
            mesh = MeshResource.generateBox(size: [size * 1.5, size * 3, size * 1.5], cornerRadius: size * 0.5)
            collisionShape = ShapeResource.generateBox(size: [size * 1.5, size * 3, size * 1.5])
        case .cone:
            // 小さな箱で代用
            mesh = MeshResource.generateBox(size: [size * 2, size * 3, size * 2], cornerRadius: 0.001)
            collisionShape = ShapeResource.generateBox(size: [size * 2, size * 3, size * 2])
        }

        // マテリアルを作成
        var material = SimpleMaterial()
        let color = UIColor(
            red: CGFloat(sharedObject.colorRGB[0]),
            green: CGFloat(sharedObject.colorRGB[1]),
            blue: CGFloat(sharedObject.colorRGB[2]),
            alpha: 1.0
        )
        material.color = .init(tint: color)
        material.roughness = 0.3
        material.metallic = 0.1

        let entity = ModelEntity(mesh: mesh, materials: [material])

        // コリジョンコンポーネントを追加
        entity.components.set(CollisionComponent(shapes: [collisionShape]))

        // 物理ボディを追加（dynamic = 動く物体）
        var physicsBody = PhysicsBodyComponent(
            shapes: [collisionShape],
            mass: 0.1,  // 100g
            mode: .dynamic
        )
        physicsBody.material = .generate(
            staticFriction: 0.5,
            dynamicFriction: 0.5,
            restitution: 0.3  // 跳ね返り係数
        )
        entity.components.set(physicsBody)

        return entity
    }

    // MARK: - Floor Management

    /// 検出した平面に床を追加（物理衝突用）
    func addFloorPlane(for anchor: ARPlaneAnchor, in arView: ARView) {
        let width = anchor.planeExtent.width
        let height = anchor.planeExtent.height

        // 透明な床メッシュを作成
        let mesh = MeshResource.generatePlane(width: width, depth: height)

        // 完全に透明なマテリアル
        var material = SimpleMaterial()
        material.color = .init(tint: .clear)

        let floorEntity = ModelEntity(mesh: mesh, materials: [material])

        // コリジョン形状
        let collisionShape = ShapeResource.generateBox(size: [width, 0.001, height])
        floorEntity.components.set(CollisionComponent(shapes: [collisionShape]))

        // 静的な物理ボディ（動かない）
        let physicsBody = PhysicsBodyComponent(
            shapes: [collisionShape],
            mass: 0,
            mode: .static
        )
        floorEntity.components.set(physicsBody)

        // 位置を設定
        floorEntity.position = [anchor.center.x, 0, anchor.center.z]

        // アンカーに追加
        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(floorEntity)
        arView.scene.addAnchor(anchorEntity)

        floorEntities[anchor.identifier] = floorEntity

        print("床面追加: \(width)m x \(height)m")
    }

    /// 床面を更新
    func updateFloorPlane(for anchor: ARPlaneAnchor) {
        guard let floorEntity = floorEntities[anchor.identifier] else { return }

        let width = anchor.planeExtent.width
        let height = anchor.planeExtent.height

        // メッシュを更新
        let mesh = MeshResource.generatePlane(width: width, depth: height)
        floorEntity.model?.mesh = mesh

        // コリジョンも更新
        let collisionShape = ShapeResource.generateBox(size: [width, 0.001, height])
        floorEntity.components.set(CollisionComponent(shapes: [collisionShape]))

        // 位置を更新
        floorEntity.position = [anchor.center.x, 0, anchor.center.z]
    }

    /// 床面を削除
    func removeFloorPlane(for anchorId: UUID) {
        if let floorEntity = floorEntities[anchorId] {
            floorEntity.removeFromParent()
            floorEntities.removeValue(forKey: anchorId)
        }
    }

    // MARK: - Static Placement

    /// タップ位置にオブジェクトを静的に配置
    func placeObject(at worldPosition: SIMD3<Float>, objectType: ObjectType) -> SharedObject? {
        let sharedObject = SharedObject(
            type: objectType,
            position: worldPosition,
            placedBy: placerId,
            colorRGB: randomObjectColor()
        )

        placedObjects.append(sharedObject)
        onObjectPlaced?(sharedObject)

        print("オブジェクト配置: \(objectType.rawValue) at \(worldPosition)")

        return sharedObject
    }

    /// スクリーン座標からワールド座標を取得
    func worldPosition(from screenPoint: CGPoint, in arView: ARView) -> SIMD3<Float>? {
        let results = arView.raycast(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any)

        guard let firstResult = results.first else {
            return nil
        }

        return SIMD3<Float>(
            firstResult.worldTransform.columns.3.x,
            firstResult.worldTransform.columns.3.y,
            firstResult.worldTransform.columns.3.z
        )
    }

    // MARK: - Receiving Shared Objects

    /// 他デバイスから受信したオブジェクトを配置
    func receivePlacement(_ sharedObject: SharedObject, in arView: ARView) {
        guard !placedObjects.contains(where: { $0.id == sharedObject.id }) else {
            return
        }

        placedObjects.append(sharedObject)

        let entity = createPhysicsEntity(for: sharedObject)
        entity.position = sharedObject.position

        let anchor = AnchorEntity(world: sharedObject.position)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        objectEntities[sharedObject.id] = entity

        print("受信オブジェクト配置: \(sharedObject.type.rawValue) at \(sharedObject.position)")
    }

    // MARK: - Object Management

    /// オブジェクトを削除
    func removeObject(id: UUID) {
        placedObjects.removeAll { $0.id == id }

        if let entity = objectEntities[id] {
            entity.removeFromParent()
            objectEntities.removeValue(forKey: id)
        }

        // タイマーをキャンセル
        deletionTimers[id]?.cancel()
        deletionTimers.removeValue(forKey: id)
    }

    /// すべてのオブジェクトをクリア
    func clearAllObjects() {
        // すべてのタイマーをキャンセル
        for timer in deletionTimers.values {
            timer.cancel()
        }
        deletionTimers.removeAll()

        for entity in objectEntities.values {
            entity.removeFromParent()
        }
        objectEntities.removeAll()
        placedObjects.removeAll()
    }

    // MARK: - Performance Optimization

    /// カメラ位置に基づいて物理シミュレーションを最適化
    /// - 遠いオブジェクトはstaticにして計算を軽減
    func optimizePhysicsForCamera(cameraPosition: SIMD3<Float>) {
        for (_, entity) in objectEntities {
            guard let modelEntity = entity as? ModelEntity else { continue }

            let distance = simd_distance(modelEntity.position(relativeTo: nil), cameraPosition)

            if distance > maxPhysicsDistance {
                // 遠いオブジェクトは物理を停止（staticに変更）
                if var physicsBody = modelEntity.components[PhysicsBodyComponent.self] {
                    if physicsBody.mode != .static {
                        physicsBody.mode = .static
                        modelEntity.components.set(physicsBody)
                    }
                }
            }
        }
    }

    // MARK: - Auto Delete

    /// 自動削除をスケジュール
    private func scheduleAutoDelete(for objectId: UUID) {
        // 既存のタイマーをキャンセル
        deletionTimers[objectId]?.cancel()

        // 新しいタイマーを開始
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(5_000_000_000)) // 5秒
                await self?.removeObject(id: objectId)
            } catch {
                // タスクがキャンセルされた場合
            }
        }
        deletionTimers[objectId] = task
    }

    /// 最大オブジェクト数を強制（古いものから削除）
    private func enforceMaxObjectCount() {
        while placedObjects.count > maxObjectCount {
            if let oldestObject = placedObjects.first {
                removeObject(id: oldestObject.id)
            }
        }
    }

    // MARK: - Helper Methods

    /// ランダムなオブジェクト色を生成
    private func randomObjectColor() -> [Float] {
        let colors: [[Float]] = [
            [0.9, 0.3, 0.2],  // 赤
            [0.2, 0.7, 0.3],  // 緑
            [0.2, 0.4, 0.9],  // 青
            [0.9, 0.7, 0.1],  // 黄
            [0.7, 0.3, 0.8],  // 紫
            [0.1, 0.8, 0.8],  // シアン
            [0.9, 0.5, 0.2],  // オレンジ
        ]
        return colors.randomElement() ?? [0.5, 0.5, 0.5]
    }

    /// エンティティを取得
    func getEntity(for objectId: UUID) -> Entity? {
        return objectEntities[objectId]
    }

    // MARK: - Reset

    /// リセット
    func reset() {
        clearAllObjects()
        for (_, floor) in floorEntities {
            floor.removeFromParent()
        }
        floorEntities.removeAll()
    }
}
