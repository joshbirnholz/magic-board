import Foundation
import MultipeerConnectivity
import UIKit

/// A separate service keeps phone sessions isolated from legacy board broadcasts.
/// MCSession supplies nearby peer-to-peer Wi-Fi/Bluetooth transport; no server is used.
final class NearbyGameConnection: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private static let service = "magic-phone"
    private let peer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var hosting = false
    private var invited: MCPeerID?
    private var reservedPeer: MCPeerID?
    var onPeers: (([MCPeerID]) -> Void)?
    var onConnection: ((MCPeerID, MCSessionState) -> Void)?
    var onData: ((Data, MCPeerID) -> Void)?
    var onError: ((String) -> Void)?
    private var peers: [MCPeerID] = []

    override init() {
        let key = "phonePlayPeerIdentity"
        if let data = UserDefaults.standard.data(forKey: key),
           let restored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            peer = restored
        } else {
            peer = MCPeerID(displayName: String(UIDevice.current.name.prefix(50)))
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: peer, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func host() {
        stop()
        hosting = true
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["mode": "duel", "version": "1"], serviceType: Self.service)
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
    }

    func browse() {
        stop()
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
    }

    func join(_ target: MCPeerID) {
        invited = target
        browser?.invitePeer(target, to: session, withContext: Data("phone-play-v1".utf8), timeout: 20)
    }

    func send(_ data: Data) throws {
        guard !session.connectedPeers.isEmpty else { throw PhoneGameError.message("Your opponent is disconnected. Reconnect before making changes.") }
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    func stop() {
        hosting = false
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session.disconnect()
        invited = nil; reservedPeer = nil
        peers = []
        onPeers?([])
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            let accepted = self.hosting && context == Data("phone-play-v1".utf8) &&
                self.session.connectedPeers.isEmpty && (self.reservedPeer == nil || self.reservedPeer == peerID)
            if accepted { self.reservedPeer = peerID }
            invitationHandler(accepted, accepted ? self.session : nil)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard info?["version"] == "1" else { return }
            if !self.peers.contains(peerID) { self.peers.append(peerID) }
            self.onPeers?(self.peers)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.peers.removeAll { $0 == peerID }
            self.onPeers?(self.peers)
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { self.onConnection?(peerID, state) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.onData?(data, peerID) }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { self.onError?(error.localizedDescription) }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { self.onError?(error.localizedDescription) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
