//
//  ShutterButtonView.swift
//  ydevARApp
//
//  シャッターボタン - AR画面のスクリーンショットを撮影
//

import SwiftUI
import RealityKit

/// シャッターボタンビュー
struct ShutterButtonView: View {

    /// ARViewへの参照（スナップショット用）
    var arView: ARView?

    /// 平面検知マネージャー（撮影時に非表示にするため）
    var planeDetectionManager: PlaneDetectionManager?

    /// 撮影完了時のコールバック
    var onCaptured: ((UIImage) -> Void)?

    /// 撮影中フラグ
    @State private var isCapturing: Bool = false

    /// 撮影成功フラグ（アニメーション用）
    @State private var showSuccess: Bool = false

    var body: some View {
        Button(action: capturePhoto) {
            ZStack {
                // 外側のリング
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)

                // 内側の円（撮影ボタン）
                Circle()
                    .fill(isCapturing ? Color.gray : Color.white)
                    .frame(width: 58, height: 58)
                    .scaleEffect(isCapturing ? 0.9 : 1.0)

                // 成功時のチェックマーク
                if showSuccess {
                    Image(systemName: "checkmark")
                        .font(.title)
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .disabled(isCapturing || arView == nil)
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    /// 写真を撮影
    private func capturePhoto() {
        guard let arView = arView else { return }

        // ハプティックフィードバック（クリック感）
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()

        isCapturing = true

        // 平面プレートを一時的に非表示
        planeDetectionManager?.setVisualizationVisible(false)

        // 少し待ってからスナップショット（描画更新のため）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // ARViewのスナップショットを取得
            arView.snapshot(saveToHDR: false) { image in
                DispatchQueue.main.async {
                    // 平面プレートを再表示
                    self.planeDetectionManager?.setVisualizationVisible(true)

                    self.isCapturing = false

                    guard let capturedImage = image else {
                        print("スナップショット取得失敗")
                        return
                    }

                    // 成功フィードバック
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)

                    // 成功アニメーション
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        self.showSuccess = true
                    }

                    // フォトライブラリに保存
                    UIImageWriteToSavedPhotosAlbum(capturedImage, nil, nil, nil)

                    // コールバック
                    self.onCaptured?(capturedImage)

                    print("写真を保存しました")

                    // 成功表示を消す
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            self.showSuccess = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.5)
        ShutterButtonView()
    }
}
