//
//  ParticipantInfo.swift
//  ydevARApp
//
//  参加者情報モデル - 空間共有時の他デバイス情報を管理
//

import Foundation
import simd
import SwiftUI

/// 参加者情報を表すモデル
/// - Note: Codableに準拠し、MultipeerConnectivity経由での送受信が可能
struct ParticipantInfo: Codable, Identifiable, Equatable {
    /// 一意の参加者ID（UUIDベース）
    let id: String

    /// 表示名（デバイス名など）
    let displayName: String

    /// 現在の3D位置（ワールド座標系）
    var position: SIMD3<Float>

    /// アバターの色（RGB値で保存）
    var colorRGB: [Float]

    /// 最終更新時刻
    var lastUpdated: Date

    /// SwiftUIのColor型へ変換
    var color: Color {
        Color(red: Double(colorRGB[0]),
              green: Double(colorRGB[1]),
              blue: Double(colorRGB[2]))
    }

    /// 初期化
    /// - Parameters:
    ///   - id: 参加者の一意ID
    ///   - displayName: 表示名
    ///   - position: 初期位置
    ///   - color: アバターの色
    init(id: String = UUID().uuidString,
         displayName: String,
         position: SIMD3<Float> = .zero,
         color: Color = .blue) {
        self.id = id
        self.displayName = displayName
        self.position = position
        self.lastUpdated = Date()

        // SwiftUI ColorからRGB値を抽出
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        self.colorRGB = [Float(red), Float(green), Float(blue)]
    }

    /// ランダムな色を生成
    static func randomColor() -> Color {
        let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .cyan, .yellow]
        return colors.randomElement() ?? .blue
    }

    static func == (lhs: ParticipantInfo, rhs: ParticipantInfo) -> Bool {
        lhs.id == rhs.id
    }
}

/// 参加者の位置更新メッセージ
struct ParticipantPositionUpdate: Codable {
    let participantId: String
    let position: SIMD3<Float>
    let timestamp: Date
}

/// メッセージタイプの識別
enum MessageType: String, Codable {
    case participantJoined
    case participantLeft
    case positionUpdate
    case objectPlaced
    case objectRemoved
    case collaborationData
}

/// 共有メッセージのラッパー
struct SharedMessage: Codable {
    let type: MessageType
    let payload: Data
    let senderId: String
    let timestamp: Date
}
