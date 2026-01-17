//
//  ARViewContainer.swift
//  ydevARApp
//
//  ARView wrapper - UIViewRepresentableパターンでARViewをSwiftUIに統合
//
//  解説ポイント:
//  - UIViewRepresentable: UIKitのビューをSwiftUIで使用するプロトコル
//  - Coordinator: デリゲートパターンとSwiftUIの橋渡し
//  - ARSessionDelegate: ARセッションのイベントを受け取る
//  - タップで物理シミュレーション付きオブジェクトを投げ入れ
//

import SwiftUI
import ARKit
import RealityKit
import Combine
import MultipeerConnectivity

/// ARViewをSwiftUIで使用するためのラッパー
struct ARViewContainer: UIViewRepresentable {

    // MARK: - Properties

    /// 平面検知マネージャー
    @ObservedObject var planeDetectionManager: PlaneDetectionManager

    /// 空間認識マネージャー
    @ObservedObject var spatialRecognitionManager: SpatialRecognitionManager

    /// 空間共有マネージャー
    @ObservedObject var spatialSharingManager: SpatialSharingManager

    /// アバターマネージャー
    @ObservedObject var avatarManager: AvatarManager

    /// オブジェクト配置マネージャー
    @ObservedObject var objectPlacementManager: ObjectPlacementManager

    /// Multipeerマネージャー
    @ObservedObject var multipeerManager: MultipeerManager

    /// オクルージョンマネージャー
    @ObservedObject var occlusionManager: OcclusionManager

    /// オブジェクト検知マネージャー
    @ObservedObject var objectDetectionManager: ObjectDetectionManager

    /// タップ位置のバインディング
    @Binding var tapLocation: CGPoint?

    /// スワイプジェスチャーのバインディング（投げ入れ用）
    @Binding var swipeGesture: SwipeGestureData?

    /// ARViewへの参照（外部アクセス用）
    @Binding var arViewReference: ARView?

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // ARセッションのデリゲートを設定
        arView.session.delegate = context.coordinator

        // セッション参照を設定
        spatialRecognitionManager.session = arView.session
        objectPlacementManager.arView = arView

        // ARセッションを開始
        let configuration = planeDetectionManager.configurePlaneDetection()

        // オクルージョン設定
        occlusionManager.configureOcclusion(in: configuration)
        occlusionManager.setupOcclusion(in: arView)

        // オブジェクト検知設定
        objectDetectionManager.configureObjectDetection(in: configuration)

        // 空間共有設定
        spatialSharingManager.enableCollaboration(in: configuration)
        arView.session.run(configuration)

        // 明るさを調整（環境光の強化）
        arView.environment.lighting.intensityExponent = 1.5

        // タップジェスチャーを追加（タップで投げ入れ）
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        // コーディネーターにARViewを設定
        context.coordinator.arView = arView

        // 外部参照用にARViewを設定
        DispatchQueue.main.async {
            self.arViewReference = arView
        }

        // アバターの位置ブロードキャスト開始
        avatarManager.startBroadcastingPosition(arView: arView)

        // コールバック設定
        setupCallbacks(context: context, arView: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // 何もしない（タップはジェスチャーで処理）
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Setup

    private func setupCallbacks(context: Context, arView: ARView) {
        // 協調データ送信コールバック
        spatialSharingManager.onCollaborationDataReady = { [weak multipeerManager] data in
            multipeerManager?.send(data)
        }

        // アバター位置ブロードキャストコールバック
        avatarManager.onPositionBroadcast = { [weak multipeerManager] update in
            if let data = try? JSONEncoder().encode(
                SharedMessage(
                    type: .positionUpdate,
                    payload: try! JSONEncoder().encode(update),
                    senderId: update.participantId,
                    timestamp: Date()
                )
            ) {
                multipeerManager?.send(data)
            }
        }

        // オブジェクト配置コールバック
        objectPlacementManager.onObjectPlaced = { [weak multipeerManager] sharedObject in
            let event = ObjectPlacementEvent(object: sharedObject, action: .placed)
            if let data = try? JSONEncoder().encode(
                SharedMessage(
                    type: .objectPlaced,
                    payload: try! JSONEncoder().encode(event),
                    senderId: sharedObject.placedBy,
                    timestamp: Date()
                )
            ) {
                multipeerManager?.send(data)
            }
        }

        // ピア接続時コールバック - 自分の参加者情報を送信
        multipeerManager.onPeerConnected = { [weak multipeerManager, weak avatarManager] peerID in
            guard let avatarManager = avatarManager else { return }

            // 自分の参加者情報を作成
            let myInfo = ParticipantInfo(
                id: avatarManager.myParticipantId,
                displayName: avatarManager.myDisplayName,
                position: .zero,
                color: ParticipantInfo.randomColor()
            )

            // 参加者情報を送信
            if let data = try? JSONEncoder().encode(
                SharedMessage(
                    type: .participantJoined,
                    payload: try! JSONEncoder().encode(myInfo),
                    senderId: avatarManager.myParticipantId,
                    timestamp: Date()
                )
            ) {
                multipeerManager?.send(data)
            }

            print("参加者情報を送信: \(avatarManager.myDisplayName)")
        }

        // ピア切断時コールバック
        multipeerManager.onPeerDisconnected = { [weak avatarManager] peerID in
            // ピアIDから参加者を削除（displayNameで検索）
            Task { @MainActor in
                if let avatarManager = avatarManager {
                    for (id, participant) in avatarManager.participants {
                        if participant.displayName == peerID.displayName {
                            avatarManager.removeParticipant(id: id)
                            break
                        }
                    }
                }
            }
        }

        // データ受信コールバック
        multipeerManager.onDataReceived = { [weak spatialSharingManager, weak avatarManager, weak objectPlacementManager] data, peerID in
            // まず協調データかどうかを試す
            if (try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: ARSession.CollaborationData.self,
                from: data
            )) != nil {
                spatialSharingManager?.applyCollaborationData(data, to: arView.session)
                return
            }

            // SharedMessageとして解析
            guard let message = try? JSONDecoder().decode(SharedMessage.self, from: data) else {
                return
            }

            Task { @MainActor in
                switch message.type {
                case .positionUpdate:
                    if let update = try? JSONDecoder().decode(ParticipantPositionUpdate.self, from: message.payload) {
                        // 参加者が存在しない場合は作成
                        if avatarManager?.participants[update.participantId] == nil {
                            let newParticipant = ParticipantInfo(
                                id: update.participantId,
                                displayName: peerID.displayName,
                                position: update.position,
                                color: ParticipantInfo.randomColor()
                            )
                            avatarManager?.addParticipant(newParticipant)

                            // アバターをシーンに追加
                            if let entity = avatarManager?.createAvatarEntity(for: newParticipant) {
                                let anchor = AnchorEntity(world: .zero)
                                anchor.addChild(entity)
                                arView.scene.addAnchor(anchor)
                            }
                        }
                        avatarManager?.updateParticipant(id: update.participantId, position: update.position)
                    }

                case .objectPlaced:
                    if let event = try? JSONDecoder().decode(ObjectPlacementEvent.self, from: message.payload) {
                        objectPlacementManager?.receivePlacement(event.object, in: arView)
                    }

                case .participantJoined:
                    if let participant = try? JSONDecoder().decode(ParticipantInfo.self, from: message.payload) {
                        // 既に存在する場合はスキップ
                        guard avatarManager?.participants[participant.id] == nil else { break }

                        avatarManager?.addParticipant(participant)
                        // アバターをシーンに追加
                        if let entity = avatarManager?.createAvatarEntity(for: participant) {
                            let anchor = AnchorEntity(world: .zero)
                            anchor.addChild(entity)
                            arView.scene.addAnchor(anchor)
                        }
                    }

                case .participantLeft:
                    avatarManager?.removeParticipant(id: message.senderId)

                default:
                    break
                }
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSessionDelegate {

        var parent: ARViewContainer
        var arView: ARView?

        /// 平面可視化用のアンカー辞書
        private var planeAnchors: [UUID: AnchorEntity] = [:]

        /// 物理床面のアンカー辞書
        private var floorAnchors: [UUID: AnchorEntity] = [:]

        /// 最適化の最終実行時刻
        private var lastOptimizationTime: Date = Date()

        /// 最適化の間隔（秒）
        private let optimizationInterval: TimeInterval = 0.5

        init(parent: ARViewContainer) {
            self.parent = parent
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let arView = arView else { return }

            for anchor in anchors {
                parent.planeDetectionManager.didAdd(anchor: anchor)

                // 平面の可視化と物理床面の追加
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    // 可視化用エンティティ
                    let planeEntity = parent.planeDetectionManager.createPlaneVisualization(for: planeAnchor)
                    let anchorEntity = AnchorEntity(anchor: planeAnchor)
                    anchorEntity.addChild(planeEntity)
                    arView.scene.addAnchor(anchorEntity)
                    planeAnchors[planeAnchor.identifier] = anchorEntity

                    // 物理衝突用の床面を追加
                    addPhysicsFloor(for: planeAnchor, in: arView)

                    // オブジェクト検知
                    Task { @MainActor in
                        parent.objectDetectionManager.detectFromPlane(planeAnchor)
                    }

                    // 平面の最適化（多すぎる場合は統合）
                    Task { @MainActor in
                        if parent.planeDetectionManager.shouldOptimize() {
                            parent.planeDetectionManager.optimizePlaneDisplay()
                        }
                    }
                }

                // メッシュアンカー処理（LiDARオクルージョン）
                if let meshAnchor = anchor as? ARMeshAnchor {
                    Task { @MainActor in
                        parent.occlusionManager.handleMeshAnchor(meshAnchor, in: arView)
                        parent.objectDetectionManager.detectFromMesh(meshAnchor, in: arView)
                    }
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                parent.planeDetectionManager.didUpdate(anchor: anchor)

                // 平面の可視化を更新
                if let planeAnchor = anchor as? ARPlaneAnchor,
                   let anchorEntity = planeAnchors[planeAnchor.identifier],
                   let planeEntity = anchorEntity.children.first as? ModelEntity {
                    parent.planeDetectionManager.updatePlaneVisualization(planeEntity, for: planeAnchor)

                    // 物理床面も更新
                    updatePhysicsFloor(for: planeAnchor)

                    // オブジェクト検知を更新
                    Task { @MainActor in
                        parent.objectDetectionManager.updateFromPlane(planeAnchor)
                    }

                    // 平面の最適化（定期的に実行）
                    Task { @MainActor in
                        parent.planeDetectionManager.optimizePlaneDisplay()
                    }
                }

                // メッシュアンカー更新（LiDAR）
                if let meshAnchor = anchor as? ARMeshAnchor {
                    Task { @MainActor in
                        parent.occlusionManager.updateMeshAnchor(meshAnchor)
                    }
                }
            }
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for anchor in anchors {
                parent.planeDetectionManager.didRemove(anchor: anchor)

                // 平面の可視化を削除
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    if let anchorEntity = planeAnchors[planeAnchor.identifier] {
                        anchorEntity.removeFromParent()
                        planeAnchors.removeValue(forKey: planeAnchor.identifier)
                    }

                    // 物理床面も削除
                    if let floorAnchor = floorAnchors[planeAnchor.identifier] {
                        floorAnchor.removeFromParent()
                        floorAnchors.removeValue(forKey: planeAnchor.identifier)
                    }

                    // オブジェクト検知からも削除
                    Task { @MainActor in
                        parent.objectDetectionManager.removeFromPlane(planeAnchor)
                    }
                }

                // メッシュアンカー削除（LiDAR）
                if let meshAnchor = anchor as? ARMeshAnchor {
                    Task { @MainActor in
                        parent.occlusionManager.removeMeshAnchor(meshAnchor)
                    }
                }
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // 空間認識状態を更新
            Task { @MainActor in
                parent.spatialRecognitionManager.updateMappingStatus(from: frame)
            }

            // 物理シミュレーションの最適化（スロットリング付き）
            let now = Date()
            if now.timeIntervalSince(lastOptimizationTime) >= optimizationInterval {
                lastOptimizationTime = now
                let cameraPosition = SIMD3<Float>(
                    frame.camera.transform.columns.3.x,
                    frame.camera.transform.columns.3.y,
                    frame.camera.transform.columns.3.z
                )
                Task { @MainActor in
                    parent.objectPlacementManager.optimizePhysicsForCamera(cameraPosition: cameraPosition)
                }
            }
        }

        func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
            // 協調データを送信
            if let serializedData = parent.spatialSharingManager.handleCollaborationData(data) {
                parent.multipeerManager.send(serializedData)
            }
        }

        // MARK: - Physics Floor Management

        /// 物理衝突用の床面を追加
        private func addPhysicsFloor(for planeAnchor: ARPlaneAnchor, in arView: ARView) {
            let width = planeAnchor.planeExtent.width
            let height = planeAnchor.planeExtent.height

            // 透明なメッシュ
            let mesh = MeshResource.generatePlane(width: width, depth: height)
            var material = SimpleMaterial()
            material.color = .init(tint: .clear)

            let floorEntity = ModelEntity(mesh: mesh, materials: [material])

            // コリジョン形状
            let collisionShape = ShapeResource.generateBox(size: [width, 0.01, height])
            floorEntity.components.set(CollisionComponent(shapes: [collisionShape]))

            // 静的な物理ボディ
            let physicsBody = PhysicsBodyComponent(
                shapes: [collisionShape],
                mass: 0,
                mode: .static
            )
            floorEntity.components.set(physicsBody)

            floorEntity.position = [planeAnchor.center.x, 0, planeAnchor.center.z]

            let anchorEntity = AnchorEntity(anchor: planeAnchor)
            anchorEntity.addChild(floorEntity)
            arView.scene.addAnchor(anchorEntity)

            floorAnchors[planeAnchor.identifier] = anchorEntity

            print("物理床面追加: \(width)m x \(height)m")
        }

        /// 物理床面を更新
        private func updatePhysicsFloor(for planeAnchor: ARPlaneAnchor) {
            guard let anchorEntity = floorAnchors[planeAnchor.identifier],
                  let floorEntity = anchorEntity.children.first as? ModelEntity else { return }

            let width = planeAnchor.planeExtent.width
            let height = planeAnchor.planeExtent.height

            // メッシュを更新
            let mesh = MeshResource.generatePlane(width: width, depth: height)
            floorEntity.model?.mesh = mesh

            // コリジョンも更新
            let collisionShape = ShapeResource.generateBox(size: [width, 0.01, height])
            floorEntity.components.set(CollisionComponent(shapes: [collisionShape]))

            // 物理ボディも更新
            let physicsBody = PhysicsBodyComponent(
                shapes: [collisionShape],
                mass: 0,
                mode: .static
            )
            floorEntity.components.set(physicsBody)

            floorEntity.position = [planeAnchor.center.x, 0, planeAnchor.center.z]
        }

        // MARK: - Gesture Handling

        /// タップで物理オブジェクトを投げ入れ
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let location = gesture.location(in: arView)

            // タップした方向にオブジェクトを投げる
            parent.objectPlacementManager.throwObjectToward(screenPoint: location, in: arView)
        }
    }
}

/// スワイプジェスチャーデータ
struct SwipeGestureData {
    let startLocation: CGPoint
    let endLocation: CGPoint
    let velocity: CGPoint
}
