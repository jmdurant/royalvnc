#if os(iOS)
import Foundation
import Network

struct BonjourServer: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
}

@MainActor
final class BonjourBrowser: ObservableObject {
    @Published var servers: [BonjourServer] = []
    @Published var isSearching = false

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isSearching = true
                case .cancelled, .failed:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for result in results {
                    if case let .service(name, _, _, _) = result.endpoint {
                        if !self.servers.contains(where: { $0.name == name }) {
                            self.resolve(result: result, name: name)
                        }
                    }
                }
            }
        }

        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        isSearching = false
    }

    private func resolve(result: NWBrowser.Result, name: String) {
        let id = name
        let connection = NWConnection(to: result.endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .ready = state {
                    if let path = connection.currentPath,
                       let endpoint = path.remoteEndpoint,
                       case let .hostPort(host, port) = endpoint {
                        let hostStr = "\(host)"
                        let portNum = port.rawValue
                        if !self.servers.contains(where: { $0.id == id }) {
                            self.servers.append(BonjourServer(id: id, name: name, host: hostStr, port: portNum))
                        }
                    }
                    connection.cancel()
                    self.resolvers.removeValue(forKey: id)
                }
            }
        }

        resolvers[id] = connection
        connection.start(queue: .main)
    }
}
#endif
