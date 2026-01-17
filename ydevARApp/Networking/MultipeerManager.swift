//
//  MultipeerManager.swift
//  ydevARApp
//
//  P2P通信クラス - MultipeerConnectivityによる近距離デバイス間通信
//
//  解説ポイント:
//  - MCSession: ピア間のセッションを管理
//  - MCPeerID: 各デバイスを識別するID
//  - MCNearbyServiceAdvertiser: 自分のサービスを広告
//  - MCNearbyServiceBrowser: 近くのサービスを検索
//  - サービスタイプ: 15文字以内、小文字とハイフンのみ
//

import Foundation
import MultipeerConnectivity
import Combine

/// 接続状態
enum ConnectionState: String {
    case disconnected = "未接続"
    case connecting = "接続中..."
    case connected = "接続完了"
    case hosting = "ホスト中"
}

/// P2P通信を管理するクラス
@MainActor
class MultipeerManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// 接続中のピアリスト
    @Published var connectedPeers: [MCPeerID] = []

    /// 接続状態
    @Published var connectionState: ConnectionState = .disconnected

    /// 発見したピア（まだ接続していない）
    @Published var discoveredPeers: [MCPeerID] = []

    /// エラーメッセージ
    @Published var errorMessage: String?

    // MARK: - Internal Properties

    /// 自分のピアID
    private let myPeerID: MCPeerID

    /// セッション
    private var session: MCSession!

    /// サービス広告者
    private var advertiser: MCNearbyServiceAdvertiser?

    /// サービス検索者
    private var browser: MCNearbyServiceBrowser?

    /// サービスタイプ（15文字以内、小文字とハイフンのみ）
    private let serviceType = "ar-collab"

    /// データ受信コールバック
    var onDataReceived: ((Data, MCPeerID) -> Void)?

    /// ピア接続時コールバック
    var onPeerConnected: ((MCPeerID) -> Void)?

    /// ピア切断時コールバック
    var onPeerDisconnected: ((MCPeerID) -> Void)?

    // MARK: - Initialization

    override init() {
        // デバイス名からピアIDを作成
        self.myPeerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        setupSession()
    }

    /// セッションをセットアップ
    private func setupSession() {
        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
    }

    // MARK: - Hosting (Advertiser)

    /// ホスティング開始（サービスを広告）
    ///
    /// 解説:
    /// - MCNearbyServiceAdvertiser: 自分のサービスを近くのデバイスに広告
    /// - discoveryInfo: 広告時に送信する追加情報（オプション）
    func startHosting() {
        stopAll()

        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        connectionState = .hosting

        // ブラウザも同時に開始（他のホストも発見できるように）
        startBrowsing()

        print("ホスティング開始: \(myPeerID.displayName)")
    }

    /// ホスティング停止
    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil

        if connectionState == .hosting {
            connectionState = connectedPeers.isEmpty ? .disconnected : .connected
        }
    }

    // MARK: - Browsing

    /// ブラウジング開始（サービスを検索）
    ///
    /// 解説:
    /// - MCNearbyServiceBrowser: 近くで広告されているサービスを検索
    /// - 発見したピアはdiscoveredPeersに追加される
    func startBrowsing() {
        browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        print("ブラウジング開始")
    }

    /// ブラウジング停止
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        discoveredPeers.removeAll()
    }

    // MARK: - Connection

    /// 発見したピアに接続を要求
    /// - Parameter peerID: 接続先のピアID
    func invitePeer(_ peerID: MCPeerID) {
        browser?.invitePeer(
            peerID,
            to: session,
            withContext: nil,
            timeout: 30
        )
        connectionState = .connecting
        print("招待を送信: \(peerID.displayName)")
    }

    // MARK: - Data Transmission

    /// すべての接続中ピアにデータを送信
    /// - Parameter data: 送信するデータ
    ///
    /// 解説:
    /// - .reliable: TCP的な信頼性のある送信（順序保証、再送あり）
    /// - .unreliable: UDP的な高速送信（順序保証なし、再送なし）
    func send(_ data: Data) {
        guard !connectedPeers.isEmpty else {
            return
        }

        do {
            try session.send(data, toPeers: connectedPeers, with: .reliable)
        } catch {
            print("データ送信エラー: \(error)")
            errorMessage = "送信エラー: \(error.localizedDescription)"
        }
    }

    /// 特定のピアにデータを送信
    /// - Parameters:
    ///   - data: 送信するデータ
    ///   - peer: 送信先のピア
    func send(_ data: Data, to peer: MCPeerID) {
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            print("データ送信エラー: \(error)")
            errorMessage = "送信エラー: \(error.localizedDescription)"
        }
    }

    // MARK: - Cleanup

    /// すべての接続を停止
    func stopAll() {
        stopHosting()
        stopBrowsing()
        session.disconnect()
        connectedPeers.removeAll()
        discoveredPeers.removeAll()
        connectionState = .disconnected
    }

    /// ピアIDを取得
    func getMyPeerID() -> MCPeerID {
        return myPeerID
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                print("接続完了: \(peerID.displayName)")
                if !connectedPeers.contains(peerID) {
                    connectedPeers.append(peerID)
                    // ピア接続コールバック
                    onPeerConnected?(peerID)
                }
                discoveredPeers.removeAll { $0 == peerID }
                connectionState = .connected

            case .connecting:
                print("接続中: \(peerID.displayName)")
                connectionState = .connecting

            case .notConnected:
                print("切断: \(peerID.displayName)")
                connectedPeers.removeAll { $0 == peerID }
                connectionState = connectedPeers.isEmpty ? .disconnected : .connected
                // ピア切断コールバック
                onPeerDisconnected?(peerID)

            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            onDataReceived?(data, peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // ストリーム受信は使用しない
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // リソース受信は使用しない
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // リソース受信は使用しない
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("招待を受信: \(peerID.displayName)")

        // 自動的に招待を受け入れる
        Task { @MainActor in
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("広告開始エラー: \(error)")
            errorMessage = "広告エラー: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            print("ピア発見: \(peerID.displayName)")

            if !discoveredPeers.contains(peerID) && !connectedPeers.contains(peerID) {
                discoveredPeers.append(peerID)

                // 自動的に接続を試みる
                invitePeer(peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("ピア消失: \(peerID.displayName)")
            discoveredPeers.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            print("ブラウジング開始エラー: \(error)")
            errorMessage = "検索エラー: \(error.localizedDescription)"
        }
    }
}
