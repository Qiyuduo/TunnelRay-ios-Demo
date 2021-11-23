import Foundation
import NetworkExtension
import TunnelRay_ios_lib
import CocoaLumberjack;
import CocoaLumberjackSwift;

let appGroup = "group.com.tunnelray.client"
let conf = """
[General]
loglevel = trace
dns-server = 223.5.5.5, 114.114.114.114
tun-fd = REPLACE-ME-WITH-THE-FD

[Proxy]
Direct = direct
REPLACE-ME-WITH-THE-CONFIG

[Proxy Group]
Fallback = fallback, VMessWSS, SS, interval=600, timeout=5

[Rule]
EXTERNAL, site:cn, Direct
FINAL, Fallback
"""

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var tunnelConfig: TunnelRayTunnel?
    private var tunnelStore: TunnelRayTunnelStore?
    
    @objc
    private enum ErrorCode: Int {
        case noError = 0
        case undefinedError = 1
        case vpnPermissionNotGranted = 2
        case vpnStartFailure = 3
        case illegalServerConfiguration = 4
    }
    
    private enum MessageKey {
        static let kActionStart = "start";
        static let kActionRestart = "restart";
        static let  kActionStop = "stop";
        static let  kActionGetTunnelId = "getTunnelId";
        static let  kActionIsReachable = "isReachable";
        static let  kMessageKeyAction = "action";
        static let  kMessageKeyTunnelId = "tunnelId";
        static let  kMessageKeyConfig = "config";
        static let  kMessageKeyErrorCode = "errorCode";
        static let  kMessageKeyHost = "host";
        static let  kMessageKeyPort = "port";
        static let  kMessageKeyOnDemand = "is-on-demand";
        static let  kDefaultPathKey = "defaultPath";
    }
    
    override private init() {
        super.init()
        tunnelStore = TunnelRayTunnelStore(appGroup: appGroup);
    }
    
    typealias ActionCompletion = (Int) -> Void
    private var startCompletion: ActionCompletion?
    private var stopCompletion: ActionCompletion?
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let tunnelConfig : TunnelRayTunnel? = self.retrieveTunnelConfig(config: options);
        if (tunnelConfig == nil) {
            DDLogError("Failed to retrieve the tunnel config.");
            completionHandler(NSError(domain: NEVPNErrorDomain, code: NEVPNError.Code.configurationInvalid.rawValue, userInfo: nil))
            return;
        }
        self.tunnelConfig = tunnelConfig;
        let tunnelNetworkSettings = getTunnelNetworkSettings()
        setTunnelNetworkSettings(tunnelNetworkSettings) { [weak self] error in
            if (error != nil) {
                DDLogError("Failed to set tunnel network settings:\(error!.localizedDescription)");
            }
            let tunFd = self?.getTunFd();
            let tunnelConfigStr = self?.getTunnelConfigStr() ?? "";
            let confWithFd = conf.replacingOccurrences(of: "REPLACE-ME-WITH-THE-FD", with: String(tunFd!)).replacingOccurrences(of: "REPLACE-ME-WITH-THE-CONFIG", with: tunnelConfigStr)
            let fileManager = FileManager.default
            let appLibraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let url : URL = appLibraryDir.appendingPathComponent("running_config.conf")
            do {
                try confWithFd.write(to: url, atomically: false, encoding: .utf8)
            } catch {
                NSLog("fialed to write config file \(error)")
            }
            let path = url.absoluteString
            let start = path.index(path.startIndex, offsetBy: 7)
            let subpath = path[start..<path.endIndex]
            DispatchQueue.global(qos: .userInteractive).async {
                signal(SIGPIPE, SIG_IGN)
                run_leaf(String(subpath))
            }
            self?.tunnelStore?.save(tunnelConfig!);
            self?.execAppCallbackForAction(action: MessageKey.kActionStart, code: ErrorCode.noError)
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        DDLogInfo("Stopping tunnel");
        self.execAppCallbackForAction(action: MessageKey.kActionStop, code: ErrorCode.noError)
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if (completionHandler == nil) {
            DDLogError("Missing message completion handler");
            return;
        }
        
        if let message = try? JSONSerialization.jsonObject(with: messageData, options: []) as? [String: Any] {
            if let action = message[MessageKey.kMessageKeyAction] as? String {
                DDLogInfo("Received app message: \(action)");
                
                let callbackWrapper = { (code: Int) in
                    var tunnelId : String?;
                    if (self.tunnelConfig != nil) {
                        tunnelId = self.tunnelConfig!.id!;
                    }
                    let response : [String: Any] = [
                        MessageKey.kMessageKeyAction: action,
                        MessageKey.kMessageKeyErrorCode: code,
                        MessageKey.kMessageKeyTunnelId: tunnelId!
                    ];
                    let jsonResponse = try? JSONSerialization.data(withJSONObject: response, options: [])
                    completionHandler!(jsonResponse);
                }
                
                if (MessageKey.kActionStart == action || MessageKey.kActionRestart == action) {
                    self.startCompletion = callbackWrapper;
                } else if (MessageKey.kActionStop == action) {
                    self.stopCompletion = callbackWrapper;
                } else if (MessageKey.kActionGetTunnelId == action) {
                    if (self.tunnelConfig != nil) {
                        let response = try? JSONSerialization.data(withJSONObject: [MessageKey.kMessageKeyTunnelId : self.tunnelConfig!.id], options: []);
                        completionHandler!(response);
                    }
                }
            } else {
                DDLogError("Missing action key in app message");
                return completionHandler!(nil);
            }
        }
        else {
            DDLogError("Failed to receive message from app");
            return;
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
    
    func getTunFd() -> Int32? {
        if #available(iOS 15, *) {
            var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            let utunPrefix = "utun".utf8CString.dropLast()
            return (0...1024).first { (_ fd: Int32) -> Bool in
                var len = socklen_t(buf.count)
                return getsockopt(fd, 2, 2, &buf, &len) == 0 && buf.starts(with: utunPrefix)
            }
        } else {
            return self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32
        }
    }
    
    func getTunnelConfigStr() -> String {
        let tunnelConfig = self.tunnelConfig
        if tunnelConfig != nil {
            if (tunnelConfig!.protocal == "ss") {
                return "SS = ss, \(tunnelConfig!.host!), \(tunnelConfig!.port!), encrypt-method=\(tunnelConfig!.method!), password=\(tunnelConfig!.password!)"
            } else if (tunnelConfig!.protocal == "vmess") {
                return "VMessWSS = vmess, \(tunnelConfig!.host!), \(tunnelConfig!.port!), username=\(tunnelConfig!.password!), ws=true, tls=true, ws-path=\(tunnelConfig!.path!)"
            } else {
                return ""
            }
        }
        return ""
    }
    
    func getTunnelNetworkSettings() -> NEPacketTunnelNetworkSettings{
        let newSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "240.0.0.10")
        newSettings.ipv4Settings = NEIPv4Settings(addresses: ["240.0.0.1"], subnetMasks: ["255.255.255.0"])
        newSettings.ipv4Settings?.includedRoutes = [NEIPv4Route.`default`()]
        newSettings.ipv4Settings?.excludedRoutes = self.getExcludedIpv4Routes()
        newSettings.proxySettings = nil
        newSettings.dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "8.8.8.8"])
        newSettings.mtu = 1500
        return newSettings
    }
    
    func getExcludedIpv4Routes() -> [NEIPv4Route] {
        var excludedIpv4Routes = [NEIPv4Route]();
        for subnet in Subnet.getReservedSubnets() {
            excludedIpv4Routes.append(NEIPv4Route(destinationAddress: subnet.address, subnetMask: subnet.mask));
        }
        return excludedIpv4Routes;
    }
    
    func retrieveTunnelConfig(config: [String: NSObject]?) -> TunnelRayTunnel? {
        var tunnelConfig: TunnelRayTunnel?;
        if (config != nil && config![MessageKey.kMessageKeyOnDemand] == nil) {
            tunnelConfig = TunnelRayTunnel(id: config![MessageKey.kMessageKeyTunnelId] as! String, configObject: config!);
        } else if (self.tunnelStore != nil) {
            DDLogInfo("Retrieving tunnelConfig from store.");
            tunnelConfig = self.tunnelStore!.load();
        }
        return tunnelConfig;
    }
    
    private func execAppCallbackForAction(action: String, code: ErrorCode) {
        if MessageKey.kActionStart == action && self.startCompletion != nil {
            self.startCompletion!(code.rawValue);
            self.startCompletion = nil;
        } else if (MessageKey.kActionStop == action && self.stopCompletion != nil){
            self.stopCompletion!(code.rawValue);
            self.stopCompletion = nil;
        } else {
            DDLogWarn("No callback for action \(action)");
        }
    }
}

