import Foundation

/// Client pentru Mac Bridge (mac_bridge.py).
/// BotBridge apeleaza Mac Bridge via WiFi pentru a porni/opri TouchRunner.
/// Mac Bridge ruleaza in fundal pe MacBook (autostart la boot via LaunchAgent).
class MacBridgeClient {
    static let shared = MacBridgeClient()

    /// IP-ul MacBook-ului pe retea locala.
    /// Detectat automat via Bonjour sau setat manual.
    @AppStorage("macBridgeHost") var host = ""
    let port = 7753

    private var baseURL: URL? {
        guard !host.isEmpty else { return nil }
        return URL(string: "http://\(host):\(port)")
    }

    // ── Public API ──────────────────────────────────────────────────────────

    /// Porneste TouchRunner pe iPhone via Mac Bridge.
    func startTouch() async -> (ok: Bool, message: String) {
        guard let base = baseURL else {
            return (false, "Mac Bridge host neconfigurat. Seteaza IP-ul MacBook-ului.")
        }
        return await call(url: base.appendingPathComponent("start"))
    }

    /// Opreste TouchRunner.
    func stopTouch() async -> (ok: Bool, message: String) {
        guard let base = baseURL else { return (true, "Neconectat") }
        return await call(url: base.appendingPathComponent("stop"))
    }

    /// Verifica daca Mac Bridge e disponibil si TouchRunner ruleaza.
    func status() async -> (available: Bool, touchRunning: Bool) {
        guard let base = baseURL else { return (false, false) }
        do {
            let (data, _) = try await URLSession.shared.data(
                from: base.appendingPathComponent("status")
            )
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (true, json["running"] as? Bool ?? false)
            }
        } catch {}
        return (false, false)
    }

    // ── Detectare automata a Mac-ului via Bonjour (NetService) ──────────────

    /// Cauta Mac Bridge in retea locala (evita configurare manuala a IP-ului).
    func autoDiscoverMac() async -> String? {
        // Incearca adresele comune de gateway + .1, .100, .101, etc.
        let gatewayPrefix = getLocalIPPrefix()
        guard !gatewayPrefix.isEmpty else { return nil }

        let candidates = [1, 100, 101, 102, 103, 104, 105, 200, 254].map {
            "\(gatewayPrefix).\($0)"
        }

        for ip in candidates {
            if let url = URL(string: "http://\(ip):\(port)/status") {
                var req = URLRequest(url: url)
                req.timeoutInterval = 0.5
                if let (data, _) = try? await URLSession.shared.data(for: req),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["bundle"] != nil {
                    return ip
                }
            }
        }
        return nil
    }

    // ── Private ──────────────────────────────────────────────────────────────

    private func call(url: URL) async -> (ok: Bool, message: String) {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let ok  = json["ok"] as? Bool ?? false
            let msg = json["msg"] as? String ?? ""
            return (ok, msg)
        } catch {
            return (false, "Mac Bridge inaccesibil: \(error.localizedDescription)")
        }
    }

    private func getLocalIPPrefix() -> String {
        // Returneaza primele 3 octeti din IP-ul local (ex: "192.168.1")
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "" }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            let flags = Int32(ptr!.pointee.ifa_flags)
            let addr  = ptr!.pointee.ifa_addr.pointee
            if addr.sa_family == UInt8(AF_INET), flags & IFF_LOOPBACK == 0 {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ptr!.pointee.ifa_addr, socklen_t(addr.sa_len),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                let parts = ip.split(separator: ".")
                if parts.count == 4, ip.hasPrefix("192.168") || ip.hasPrefix("10.") {
                    return parts.prefix(3).joined(separator: ".")
                }
            }
            ptr = ptr!.pointee.ifa_next
        }
        return ""
    }
}
