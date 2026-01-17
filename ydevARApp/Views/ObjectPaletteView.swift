//
//  ObjectPaletteView.swift
//  ydevARApp
//
//  オブジェクト選択UI - 投げ入れるオブジェクトの選択パレット
//

import SwiftUI

/// オブジェクト選択パレットビュー
struct ObjectPaletteView: View {

    @ObservedObject var objectPlacementManager: ObjectPlacementManager

    var body: some View {
        VStack(spacing: 12) {
            // オブジェクト選択パレット
            objectPalette

            // 投げる強さスライダー
            throwStrengthSlider

            // 操作ヒント
            Text("画面をタップしてオブジェクトを投げ入れ")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Subviews

    private var objectPalette: some View {
        HStack(spacing: 16) {
            ForEach(ObjectType.allCases) { objectType in
                ObjectButton(
                    objectType: objectType,
                    isSelected: objectPlacementManager.selectedObjectType == objectType
                ) {
                    objectPlacementManager.selectedObjectType = objectType
                }
            }
        }
    }

    private var throwStrengthSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left")
                .font(.caption)
                .foregroundColor(.secondary)

            Slider(
                value: $objectPlacementManager.throwStrength,
                in: 0.5...3.0,
                step: 0.1
            )
            .tint(.blue)

            Image(systemName: "hand.point.up.left.fill")
                .font(.caption)
                .foregroundColor(.blue)

            Text(String(format: "%.1fx", objectPlacementManager.throwStrength))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 35)
        }
        .padding(.horizontal, 8)
    }
}

/// 個別のオブジェクトボタン
struct ObjectButton: View {

    let objectType: ObjectType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // オブジェクトアイコン
                objectIcon
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )

                // オブジェクト名
                Text(objectType.rawValue)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var objectIcon: some View {
        switch objectType {
        case .cube:
            Image(systemName: "cube.fill")
                .foregroundColor(.orange)
        case .sphere:
            Image(systemName: "circle.fill")
                .foregroundColor(.blue)
        case .cylinder:
            Image(systemName: "cylinder.fill")
                .foregroundColor(.green)
        case .cone:
            Image(systemName: "cone.fill")
                .foregroundColor(.purple)
        }
    }
}

// MARK: - Object Count View

/// 配置済みオブジェクト数を表示
struct ObjectCountView: View {

    @ObservedObject var objectPlacementManager: ObjectPlacementManager

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cube.fill")
                .font(.caption)
            Text("\(objectPlacementManager.placedObjects.count)個配置済み")
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

// MARK: - Clear Button

/// オブジェクトクリアボタン
struct ClearObjectsButton: View {

    @ObservedObject var objectPlacementManager: ObjectPlacementManager
    @State private var showConfirmation = false

    var body: some View {
        Button(action: {
            showConfirmation = true
        }) {
            Image(systemName: "trash")
                .font(.title3)
                .foregroundColor(.red)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .disabled(objectPlacementManager.placedObjects.isEmpty)
        .opacity(objectPlacementManager.placedObjects.isEmpty ? 0.5 : 1.0)
        .alert("確認", isPresented: $showConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("すべて削除", role: .destructive) {
                objectPlacementManager.clearAllObjects()
            }
        } message: {
            Text("配置したオブジェクトをすべて削除しますか？")
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        ObjectPaletteView(objectPlacementManager: ObjectPlacementManager())
    }
    .background(Color.black)
}
