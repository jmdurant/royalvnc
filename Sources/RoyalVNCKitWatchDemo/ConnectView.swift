import SwiftUI
import RoyalVNCKit

struct ConnectView: View {
    @State private var hostname = ""
    @State private var port = "5900"
    @State private var username = ""
    @State private var password = ""
    @StateObject private var browser = BonjourBrowser()

    var body: some View {
        NavigationStack {
            Form {
                if !browser.servers.isEmpty {
                    Section("Nearby Servers") {
                        ForEach(browser.servers) { server in
                            NavigationLink {
                                SessionView(
                                    hostname: server.host,
                                    port: server.port,
                                    username: username,
                                    password: password
                                )
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                        .font(.body)
                                    Text("\(server.host):\(server.port)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if browser.isSearching {
                    Section("Nearby Servers") {
                        HStack {
                            ProgressView()
                            Text("Searching...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Manual") {
                    TextField("Hostname", text: $hostname)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    TextField("Port", text: $port)
                }

                Section("Authentication") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    SecureField("Password", text: $password)
                }

                Section {
                    NavigationLink {
                        SessionView(
                            hostname: hostname,
                            port: UInt16(port) ?? 5900,
                            username: username,
                            password: password
                        )
                    } label: {
                        Text("Connect")
                    }
                    .disabled(hostname.isEmpty)
                }
            }
            .navigationTitle("RoyalVNC")
            .onAppear {
                browser.startBrowsing()
            }
            .onDisappear {
                browser.stopBrowsing()
            }
        }
    }
}
