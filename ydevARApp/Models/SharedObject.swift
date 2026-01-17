//
//  SharedObject.swift
//  ydevARApp
//
//  共有オブジェクトモデル - 空間に配置される3Dオブジェクトの情報
//

import Foundation
import simd

/// 配置可能なオブジェクトの種類
enum ObjectType: String, Codable, CaseIterable, Identifiable {
    case cube = "立方体"
    case sphere = "球体"
    case cylinder = "円柱"
    case cone = "コーン"

    var id: String { rawValue }

    /// UI表示用のシンボル名
    var symbolName: String {
        switch self {
        case .cube: return "square.fill"
        case .sphere: return "circle.fill"
        case .cylinder: return "cylinder.fill"
        case .cone: return "triangle.fill"
        }
    }

    /// オブジェクトのデフォルトサイズ（2倍サイズ）
    var defaultSize: Float {
        switch self {
        case .cube: return 0.10      // 元: 0.05 → 2倍
        case .sphere: return 0.05    // 元: 0.025 → 2倍
        case .cylinder: return 0.06  // 元: 0.03 → 2倍
        case .cone: return 0.08      // 元: 0.04 → 2倍
        }
    }
}

/// 空間に配置されるオブジェクトの情報
struct SharedObject: Codable, Identifiable, Equatable {
    /// オブジェクトの一意ID
    let id: UUID

    /// オブジェクトの種類
    let type: ObjectType

    /// 3D位置（ワールド座標系）
    var position: SIMD3<Float>

    /// 回転（クォータニオン）
    var rotation: simd_quatf

    /// スケール
    var scale: Float

    /// 配置したユーザーのID
    let placedBy: String

    /// 配置日時
    let placedAt: Date

    /// オブジェクトの色（RGB）
    var colorRGB: [Float]

    /// 初期化
    init(type: ObjectType,
         position: SIMD3<Float>,
         rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
         scale: Float = 1.0,
         placedBy: String,
         colorRGB: [Float] = [0.8, 0.3, 0.2]) {
        self.id = UUID()
        self.type = type
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.placedBy = placedBy
        self.placedAt = Date()
        self.colorRGB = colorRGB
    }

    static func == (lhs: SharedObject, rhs: SharedObject) -> Bool {
        lhs.id == rhs.id
    }
}

/// オブジェクト配置イベント
struct ObjectPlacementEvent: Codable {
    let object: SharedObject
    let action: PlacementAction

    enum PlacementAction: String, Codable {
        case placed
        case removed
        case updated
    }
}

// MARK: - Codable Extension for simd_quatf
extension simd_quatf: @retroactive Decodable, @retroactive Encodable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let ix = try container.decode(Float.self)
        let iy = try container.decode(Float.self)
        let iz = try container.decode(Float.self)
        let r = try container.decode(Float.self)
        self.init(ix: ix, iy: iy, iz: iz, r: r)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(imag.x)
        try container.encode(imag.y)
        try container.encode(imag.z)
        try container.encode(real)
    }
}
