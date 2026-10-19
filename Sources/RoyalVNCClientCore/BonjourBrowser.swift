#if canImport(Network) && canImport(Combine)
import Foundation
import Combine
import Network

public struct DiscoveredServer: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let host: String
    public let port: UInt16

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

public typealias BonjourServer = DiscoveredServer

@MainActor
public final class BonjourBrowser: ObservableObject {
    @Published public var servers: [DiscoveredServer] = []
    @Published public var isSearching = false

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]
    private var advertisedIDs: Set<String> = []
    private var generation = UUID()

    public init() {}

    deinit {
        browser?.cancel()
        resolvers.values.forEach { $0.cancel() }
    }

    public func startBrowsing() {
        stopBrowsing()
        servers = []
        let generation = self.generation
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: nil), using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                switch state {
                case .ready: self.isSearching = true
                case .failed, .cancelled: self.isSearching = false
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.handleResults(results)
            }
        }
        browser.start(queue: .main)
    }

    public func stopBrowsing() {
        generation = UUID()
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        advertisedIDs.removeAll()
        isSearching = false
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        advertisedIDs = Set(results.compactMap { Self.identity($0.endpoint) })
        servers.removeAll { !advertisedIDs.contains($0.id) }
        for id in Array(resolvers.keys) where !advertisedIDs.contains(id) {
            resolvers.removeValue(forKey: id)?.cancel()
        }
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint,
                  let id = Self.identity(result.endpoint),
                  !servers.contains(where: { $0.id == id }), resolvers[id] == nil else { continue }
            resolve(endpoint: result.endpoint, name: name, id: id)
        }
    }

    private static func identity(_ endpoint: NWEndpoint) -> String? {
        guard case let .service(name, type, domain, interface) = endpoint else { return nil }
        return "\(name).\(type).\(domain).\(interface?.index ?? 0)"
    }

    private func resolve(endpoint: NWEndpoint, name: String, id: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let generation = self.generation
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, self.generation == generation,
                      self.resolvers[id] === connection else { return }
                switch state {
                case .ready:
                    if self.advertisedIDs.contains(id),
                       let endpoint = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(host, port) = endpoint {
                        let hostname: String
                        switch host {
                        case .name(let value, _): hostname = value
                        case .ipv4(let value): hostname = "\(value)"
                        case .ipv6(let value): hostname = "\(value)"
                        @unknown default: hostname = "\(host)"
                        }
                        if !self.servers.contains(where: { $0.id == id }) {
                            self.servers.append(DiscoveredServer(id: id, name: name, host: hostname, port: port.rawValue))
                        }
                    }
                    self.resolvers.removeValue(forKey: id)
                    connection.cancel()
                case .failed, .cancelled:
                    self.resolvers.removeValue(forKey: id)
                default: break
                }
            }
        }
        resolvers[id] = connection
        connection.start(queue: .main)
    }
}
#endif
