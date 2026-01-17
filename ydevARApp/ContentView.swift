//
//  ContentView.swift
//  ydevARApp
//
//  メインUI - 全コンポーネントの統合
//
//  機能:
//  - 平面検知と可視化
//  - 空間認識（ワールドマッピング）
//  - 空間共有（Collaborative Session）
//  - 参加者アバター表示
//  - 3Dオブジェクトの配置・投げ入れ
//

import SwiftUI
import RealityKit
import ARKit
import MultipeerConnectivity
import Photos

struct ContentView: View {

    // MARK: - State Objects

    /// 平面検知マネージャー
    @StateObject private var planeDetectionManager = PlaneDetectionManager()

    /// 空間認識マネージャー
    @StateObject private var spatialRecognitionManager = SpatialRecognitionManager()

    /// 空間共有マネージャー
    @StateObject private var spatialSharingManager = SpatialSharingManager()

    /// アバターマネージャー
    @StateObject private var avatarManager = AvatarManager()

    /// オブジェクト配置マネージャー
    @StateObject private var objectPlacementManager = ObjectPlacementManager()

    /// Multipeerマネージャー
    @StateObject private var multipeerManager = MultipeerManager()

    /// オクルージョンマネージャー
    @StateObject private var occlusionManager = OcclusionManager()

    /// オブジェクト検知マネージャー
    @StateObject private var objectDetectionManager = ObjectDetectionManager()

    // MARK: - State

    /// タップ位置
    @State private var tapLocation: CGPoint?

    /// スワイプジェスチャーデータ
    @State private var swipeGesture: SwipeGestureData?

    /// 設定パネル表示フラグ
    @State private var showSettings = false

    /// ARViewへの参照（スナップショット用）
    @State private var arViewReference: ARView?

    // MARK: - Body

    var body: some View {
        ZStack {
            // ARビュー
            ARViewContainer(
                planeDetectionManager: planeDetectionManager,
                spatialRecognitionManager: spatialRecognitionManager,
                spatialSharingManager: spatialSharingManager,
                avatarManager: avatarManager,
                objectPlacementManager: objectPlacementManager,
                multipeerManager: multipeerManager,
                occlusionManager: occlusionManager,
                objectDetectionManager: objectDetectionManager,
                tapLocation: $tapLocation,
                swipeGesture: $swipeGesture,
                arViewReference: $arViewReference
            )
            .edgesIgnoringSafeArea(.all)

            // UIオーバーレイ
            VStack {
                // 上部: 接続状態
                ConnectionStatusView(
                    multipeerManager: multipeerManager,
                    spatialRecognitionManager: spatialRecognitionManager,
                    spatialSharingManager: spatialSharingManager,
                    planeDetectionManager: planeDetectionManager,
                    occlusionManager: occlusionManager,
                    objectDetectionManager: objectDetectionManager
                )
                .padding(.top, 50)

                Spacer()

                // 右下: コントロールボタン
                HStack {
                    Spacer()

                    VStack(spacing: 12) {
                        // 設定ボタン
                        settingsButton

                        // クリアボタン
                        ClearObjectsButton(objectPlacementManager: objectPlacementManager)

                        // オブジェクトカウント
                        ObjectCountView(objectPlacementManager: objectPlacementManager)
                    }
                    .padding(.trailing, 16)
                }

                // 下部: シャッターボタン + オブジェクトパレット
                HStack(alignment: .bottom, spacing: 16) {
                    // シャッターボタン（左側）
                    ShutterButtonView(
                        arView: arViewReference,
                        planeDetectionManager: planeDetectionManager
                    )
                    .padding(.leading, 16)

                    // オブジェクトパレット
                    ObjectPaletteView(objectPlacementManager: objectPlacementManager)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            setupManagers()
            startMultipeer()
            requestPhotoLibraryPermission()
        }
        .onDisappear {
            cleanup()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                multipeerManager: multipeerManager,
                spatialSharingManager: spatialSharingManager,
                avatarManager: avatarManager
            )
        }
    }

    // MARK: - Subviews

    private var settingsButton: some View {
        Button(action: {
            showSettings = true
        }) {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundColor(.primary)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }

    // MARK: - Setup

    private func setupManagers() {
        // オブジェクト配置マネージャーに配置者IDを設定
        objectPlacementManager.placerId = avatarManager.myParticipantId
    }

    private func startMultipeer() {
        // ホスティング開始（自動的に他のデバイスを検索・接続）
        multipeerManager.startHosting()
    }

    private func cleanup() {
        multipeerManager.stopAll()
        avatarManager.reset()
        objectPlacementManager.reset()
        occlusionManager.reset()
        objectDetectionManager.reset()
    }

    /// 写真ライブラリのパーミッションをリクエスト
    private func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                print("写真ライブラリへのアクセスが許可されました")
            case .denied, .restricted:
                print("写真ライブラリへのアクセスが拒否されました")
            case .notDetermined:
                print("写真ライブラリへのアクセスが未決定です")
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {

    @ObservedObject var multipeerManager: MultipeerManager
    @ObservedObject var spatialSharingManager: SpatialSharingManager
    @ObservedObject var avatarManager: AvatarManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // 接続セクション
                Section("接続") {
                    HStack {
                        Text("デバイス名")
                        Spacer()
                        Text(avatarManager.myDisplayName)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("接続状態")
                        Spacer()
                        Text(multipeerManager.connectionState.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("接続中のデバイス")
                        Spacer()
                        Text("\(multipeerManager.connectedPeers.count)")
                            .foregroundColor(.secondary)
                    }

                    if !multipeerManager.connectedPeers.isEmpty {
                        ForEach(multipeerManager.connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundColor(.blue)
                                Text(peer.displayName)
                            }
                        }
                    }
                }

                // 空間共有セクション
                Section("空間共有") {
                    HStack {
                        Text("共有機能")
                        Spacer()
                        Text(spatialSharingManager.isSharingEnabled ? "有効" : "無効")
                            .foregroundColor(spatialSharingManager.isSharingEnabled ? .green : .red)
                    }

                    HStack {
                        Text("協調確立")
                        Spacer()
                        Text(spatialSharingManager.isCollaborationEstablished ? "はい" : "いいえ")
                            .foregroundColor(spatialSharingManager.isCollaborationEstablished ? .green : .secondary)
                    }

                    HStack {
                        Text("送信データ量")
                        Spacer()
                        Text(formatBytes(spatialSharingManager.dataSentBytes))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("受信データ量")
                        Spacer()
                        Text(formatBytes(spatialSharingManager.dataReceivedBytes))
                            .foregroundColor(.secondary)
                    }
                }

                // アクションセクション
                Section("アクション") {
                    Button("接続をリセット") {
                        multipeerManager.stopAll()
                        multipeerManager.startHosting()
                    }
                    .foregroundColor(.orange)

                    Button("統計をリセット") {
                        spatialSharingManager.resetStatistics()
                    }
                }

                // 情報セクション
                Section("情報") {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("参加者ID")
                        Spacer()
                        Text(avatarManager.myParticipantId.prefix(8) + "...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
