import Foundation
import TunnelRay_ios_lib

@objcMembers
class TunnelRayTunnelStore: NSObject {
    // TODO(alalama): s/connection/tunnel when we update the schema.
    private static let kTunnelStoreKey = "connectionStore"
    private static let kTunnelStatusKey = "connectionStatus"
    
    private let defaults: UserDefaults?
    
    // Constructs the store with UserDefaults as the storage.
    required init(appGroup: String) {
        defaults = UserDefaults(suiteName: appGroup)
        super.init()
    }
    
    // Loads a previously saved tunnel from the store.
    func load() -> TunnelRayTunnel? {
        if let encodedTunnel = defaults?.data(forKey: TunnelRayTunnelStore.kTunnelStoreKey) {
            return TunnelRayTunnel.decode(encodedTunnel)
        }
        return nil
    }
    
    // Writes |tunnel| to the store.
    @discardableResult
    func save(_ tunnel: TunnelRayTunnel) -> Bool {
        if let encodedTunnel = tunnel.encode() {
            defaults?.set(encodedTunnel, forKey: TunnelRayTunnelStore.kTunnelStoreKey)
        }
        return true
    }
    
    var status: TunnelRayTunnel.TunnelStatus {
        get {
            let status = defaults?.integer(forKey: TunnelRayTunnelStore.kTunnelStatusKey)
                ?? TunnelRayTunnel.TunnelStatus.disconnected.rawValue
            return TunnelRayTunnel.TunnelStatus(rawValue:status)
                ?? TunnelRayTunnel.TunnelStatus.disconnected
        }
        set(newStatus) {
            defaults?.set(newStatus.rawValue, forKey: TunnelRayTunnelStore.kTunnelStatusKey)
        }
    }
}

