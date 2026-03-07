import Foundation
import Network

struct DiscoveredServer: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class BonjourBrowser: ObservableObject {
    @Published var servers: [DiscoveredServer] = []
    @Published var isSearching = false

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]

    func startBrowsing() {
        stopBrowsing()

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: nil), using: params)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.handleResults(results)
            }
        }

        browser.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        isSearching = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }

            let id = "\(name).\(type).\(domain)"

            // Skip if already discovered
            if servers.contains(where: { $0.id == id }) { continue }

            // Resolve the service to get host and port
            resolve(name: name, type: type, domain: domain, id: id)
        }

        // Remove servers that are no longer advertised
        let currentIDs = results.compactMap { result -> String? in
            guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
            return "\(name).\(type).\(domain)"
        }
        servers.removeAll { !currentIDs.contains($0.id) }
    }

    private func resolve(name: String, type: String, domain: String, id: String) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }

            let host: String
            let port: UInt16

            if let path = connection.currentPath,
               let remoteEndpoint = path.remoteEndpoint,
               case let .hostPort(h, p) = remoteEndpoint {
                switch h {
                case .name(let hostname, _):
                    host = hostname
                case .ipv4(let addr):
                    host = "\(addr)"
                case .ipv6(let addr):
                    host = "\(addr)"
                @unknown default:
                    host = name
                }
                port = p.rawValue
            } else {
                host = name
                port = 5900
            }

            let server = DiscoveredServer(id: id, name: name, host: host, port: port)

            Task { @MainActor [weak self] in
                if let self, !self.servers.contains(where: { $0.id == id }) {
                    self.servers.append(server)
                }
            }

            connection.cancel()

            Task { @MainActor [weak self] in
                self?.resolvers.removeValue(forKey: id)
            }
        }

        resolvers[id] = connection
        connection.start(queue: .main)
    }
}
