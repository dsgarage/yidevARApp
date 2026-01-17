# ydevARApp

[yidev 第五十二回勉強会](https://yidev4.connpass.com/event/377507/) 用のARサンプルアプリです。

## TestFlight

以下のリンクからインストールできます：

**[TestFlightでインストール](https://testflight.apple.com/join/P8zMe1u3)**

## 機能

### 平面検知
- 水平面（床、テーブル）を自動検出
- 半透明のプレートで可視化
- 複数平面の自動最適化・統合

### 3Dオブジェクト配置
- タップで平面上にオブジェクトを配置
- スワイプで物理演算による投げ入れ
- 選択可能なオブジェクト：立方体、球体、円柱、コーン
- 5秒後に自動消去

### 空間共有（マルチプレイヤー）
- 近くのデバイスと自動接続（MultipeerConnectivity）
- ARKit Collaborative Sessionによるリアルタイム空間同期
- 他の参加者の位置をアバターで表示
- 配置したオブジェクトを全員で共有

### オクルージョン
- LiDAR対応デバイスでシーンオクルージョン
- 人物オクルージョン（人の後ろに3Dオブジェクトが隠れる）

### 写真撮影
- シャッターボタンで写真撮影
- 触覚フィードバック付き
- 平面検知プレートは写真に映らない

## 技術スタック

- **言語**: Swift
- **最小iOS**: 17.0
- **フレームワーク**:
  - ARKit（空間認識）
  - RealityKit（3Dレンダリング）
  - MultipeerConnectivity（P2P通信）

## プロジェクト構成

```
ydevARApp/
├── AR/
│   ├── PlaneDetectionManager.swift     # 平面検知
│   ├── SpatialRecognitionManager.swift # 空間認識（ワールドマッピング）
│   ├── SpatialSharingManager.swift     # 空間共有（Collaborative Session）
│   ├── AvatarManager.swift             # 参加者アバター
│   ├── ObjectPlacementManager.swift    # オブジェクト配置・物理演算
│   ├── OcclusionManager.swift          # オクルージョン
│   └── ObjectDetectionManager.swift    # オブジェクト検知
├── Networking/
│   └── MultipeerManager.swift          # P2P通信
├── Models/
│   ├── ParticipantInfo.swift           # 参加者情報
│   └── SharedObject.swift              # 共有オブジェクト
├── Views/
│   ├── ARViewContainer.swift           # ARView wrapper
│   ├── ConnectionStatusView.swift      # 接続状態UI
│   ├── ObjectPaletteView.swift         # オブジェクト選択UI
│   └── ShutterButtonView.swift         # シャッターボタン
└── ContentView.swift                   # メインUI
```

## 操作方法

| 操作 | アクション |
|-----|----------|
| タップ | 選択中のオブジェクトを配置 |
| スワイプ | オブジェクトを投げ入れ |
| 下部パレット | オブジェクトの種類を選択 |
| シャッターボタン | 写真撮影 |
| 歯車アイコン | 設定画面 |

## 必要な権限

- カメラ（AR体験用）
- ローカルネットワーク（デバイス間通信用）
- 写真ライブラリ（写真保存用）

## ドキュメント

`docs/` フォルダに勉強会用の資料があります：

- `01_introduction.md` - ARの基礎知識
- `02_SDK.md` - ARKit/RealityKit/SceneKitの解説
- `03_Build.md` - 共有AR機能の実装解説

## ライセンス

MIT License

## 作者

[@dsgarage](https://github.com/dsgarage)
