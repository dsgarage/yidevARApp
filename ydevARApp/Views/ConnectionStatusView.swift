//
//  ConnectionStatusView.swift
//  ydevARApp
//
//  接続状態UI - 参加者数や接続状態を表示
//

import SwiftUI
import MultipeerConnectivity

/// 接続状態を表示するビュー
struct ConnectionStatusView: View {

    @ObservedObject var multipeerManager: MultipeerManager
    @ObservedObject var spatialRecognitionManager: SpatialRecognitionManager
    @ObservedObject var spatialSharingManager: SpatialSharingManager
    @ObservedObject var planeDetectionManager: PlaneDetectionManager
    var occlusionManager: OcclusionManager? = nil
    var objectDetectionManager: ObjectDetectionManager? = nil

    var body: some View {
        VStack(spacing: 8) {
            // 接続状態バー
            HStack(spacing: 12) {
                // 接続インジケーター
                connectionIndicator

                // 参加者数
                participantCount

                Spacer()

                // マッピング状態
                mappingStatus
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            // 詳細情報（展開可能）
            if showDetails {
                detailsView
            }
        }
    }

    @State private var showDetails: Bool = false

    // MARK: - Subviews

    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 10, height: 10)

            Text(multipeerManager.connectionState.rawValue)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .onTapGesture {
            withAnimation {
                showDetails.toggle()
            }
        }
    }

    private var participantCount: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.caption)

            Text("\(multipeerManager.connectedPeers.count + 1)人参加中")
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }

    private var mappingStatus: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(mappingColor)
                .frame(width: 8, height: 8)

            Text(spatialRecognitionManager.mappingQuality.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 検出された平面
            HStack {
                Image(systemName: "square.grid.2x2")
                Text("検出平面: 水平 \(planeDetectionManager.horizontalPlaneCount) / 垂直 \(planeDetectionManager.verticalPlaneCount)")
                    .font(.caption2)
            }

            // 特徴点
            HStack {
                Image(systemName: "sparkles")
                Text("特徴点: \(spatialRecognitionManager.featurePointCount)")
                    .font(.caption2)
            }

            // 協調データ
            if spatialSharingManager.isSharingEnabled {
                HStack {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("送信: \(formatBytes(spatialSharingManager.dataSentBytes)) / 受信: \(formatBytes(spatialSharingManager.dataReceivedBytes))")
                        .font(.caption2)
                }
            }

            // オクルージョン
            if let occlusion = occlusionManager {
                HStack {
                    Image(systemName: "eye.slash")
                    Text("オクルージョン: 人物\(occlusion.isPeopleOcclusionEnabled ? "ON" : "OFF") / シーン\(occlusion.isSceneOcclusionEnabled ? "ON" : "OFF")")
                        .font(.caption2)
                }
            }

            // オブジェクト検知
            if let detection = objectDetectionManager {
                HStack {
                    Image(systemName: "cube.transparent")
                    Text("検知: \(detection.detectedObjects.count)個")
                        .font(.caption2)
                }

                if !detection.classificationCounts.isEmpty {
                    HStack {
                        ForEach(Array(detection.classificationCounts.keys), id: \.self) { classification in
                            if let count = detection.classificationCounts[classification], count > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: classification.symbolName)
                                        .foregroundColor(Color(classification.color))
                                    Text("\(count)")
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }
            }

            // 接続中のピア
            if !multipeerManager.connectedPeers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("接続中:")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    ForEach(multipeerManager.connectedPeers, id: \.displayName) { peer in
                        HStack {
                            Image(systemName: "iphone")
                            Text(peer.displayName)
                                .font(.caption2)
                        }
                        .padding(.leading, 8)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    // MARK: - Computed Properties

    private var connectionColor: Color {
        switch multipeerManager.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .hosting:
            return .blue
        case .disconnected:
            return .red
        }
    }

    private var mappingColor: Color {
        switch spatialRecognitionManager.mappingQuality {
        case .mapped:
            return .green
        case .extending:
            return .yellow
        case .limited:
            return .orange
        case .notAvailable:
            return .red
        }
    }

    // MARK: - Helpers

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
    ConnectionStatusView(
        multipeerManager: MultipeerManager(),
        spatialRecognitionManager: SpatialRecognitionManager(),
        spatialSharingManager: SpatialSharingManager(),
        planeDetectionManager: PlaneDetectionManager()
    )
}
