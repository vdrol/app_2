import Foundation
import MultipeerConnectivity

/// Connects phones in the same "room" over peer-to-peer Wi‑Fi and Bluetooth (no internet
/// or router needed) and exchanges `CaptionEntry` messages.
///
/// Every phone advertises and browses at the same time. When two phones find each other,
/// only the one with the smaller device ID sends the invitation, so they never both
/// invite each other at once and end up with two half-open connections.
final class PeerSession: NSObject {
    /// Must match `NSBonjourServices` in Info.plist (`_tablecaptions._tcp` / `_udp`).
    static let serviceType = "tablecaptions"

    /// Called on the main thread.
    var onCaption: (@Sendable (CaptionEntry) -> Void)?
    /// Called on the main thread with the display names of connected phones.
    var onPeersChanged: (@Sendable ([String]) -> Void)?
    /// Called on the main thread.
    var onError: (@Sendable (Error) -> Void)?

    private let deviceID: String
    private var roomCode = ""
    private var peerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(deviceID: String, displayName: String) {
        self.deviceID = deviceID
        peerID = MCPeerID(displayName: Self.peerName(displayName))
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
    }

    var isActive: Bool { advertiser != nil }

    func start(room: String, displayName: String) {
        stop()
        roomCode = room
        peerID = MCPeerID(displayName: Self.peerName(displayName))
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        let advertiser = MCNearbyServiceAdvertiser(peer: peerID,
                                                   discoveryInfo: ["id": deviceID, "room": room],
                                                   serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session.delegate = nil
        session.disconnect()
        onPeersChanged?([])
    }

    func send(_ entry: CaptionEntry) {
        let peers = session.connectedPeers
        guard !peers.isEmpty, let data = try? encoder.encode(entry) else { return }
        // Updates in progress are sent unreliably (a newer one will replace them anyway);
        // final captions must arrive.
        try? session.send(data, toPeers: peers, with: entry.isFinal ? .reliable : .unreliable)
    }

    /// MCPeerID display names must be non-empty and at most 63 bytes.
    private static func peerName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmed.isEmpty ? "Roundtable" : trimmed
        while result.utf8.count > 63 { result.removeLast() }
        return result
    }

    private func restartBrowsing() {
        guard let browser else { return }
        // Browsing again re-reports peers that are still nearby, so a dropped connection is re-made.
        browser.stopBrowsingForPeers()
        browser.startBrowsingForPeers()
    }
}

extension PeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let info, info["room"] == roomCode,
              let theirID = info["id"], theirID != deviceID,
              deviceID < theirID,
              !session.connectedPeers.contains(peerID)
        else { return }
        browser.invitePeer(peerID, to: session, withContext: Data(roomCode.utf8), timeout: 15)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { self.onError?(error) }
    }
}

extension PeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let room = context.flatMap { String(data: $0, encoding: .utf8) }
        let accept = room == roomCode
        invitationHandler(accept, accept ? session : nil)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { self.onError?(error) }
    }
}

extension PeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let names = session.connectedPeers.map(\.displayName)
        DispatchQueue.main.async {
            guard session === self.session else { return }
            self.onPeersChanged?(names)
            if state == .notConnected { self.restartBrowsing() }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let entry = try? decoder.decode(CaptionEntry.self, from: data) else { return }
        DispatchQueue.main.async {
            guard session === self.session else { return }
            self.onCaption?(entry)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
