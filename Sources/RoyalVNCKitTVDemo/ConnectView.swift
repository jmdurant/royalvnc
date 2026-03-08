#if os(tvOS)
import SwiftUI
import RoyalVNCKit

struct ConnectView: View {
    @State private var hostname = ""
    @State private var port = "5900"
    @State private var savedProfiles: [ServerProfile] = []
    @StateObject private var browser = BonjourBrowser()
    @State private var activeSession: SessionTarget?
    @State private var showingCreateConnection = false

    var body: some View {
        NavigationView {
            List {
                // Nearby Servers
                if !browser.servers.isEmpty {
                    Section(header: Text("Nearby Servers")) {
                        ForEach(browser.servers) { server in
                            Button {
                                activeSession = SessionTarget(hostname: server.host, port: server.port)
                            } label: {
                                HStack {
                                    Image(systemName: "display")
                                        .font(.title2)
                                    VStack(alignment: .leading) {
                                        Text(server.name)
                                            .font(.headline)
                                        Text("\(server.host):\(server.port)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                } else if browser.isSearching {
                    Section(header: Text("Nearby Servers")) {
                        HStack {
                            ProgressView()
                            Text("Searching for servers...")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Saved Profiles
                if !savedProfiles.isEmpty {
                    Section(header: Text("Saved")) {
                        ForEach(savedProfiles) { profile in
                            Button {
                                activeSession = SessionTarget(hostname: profile.hostname, port: profile.port)
                            } label: {
                                HStack {
                                    Image(systemName: "bookmark.fill")
                                        .font(.title2)
                                    VStack(alignment: .leading) {
                                        Text(profile.name)
                                            .font(.headline)
                                        Text("\(profile.hostname):\(profile.port)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .onDelete(perform: deleteProfiles)
                    }
                }

                // Create New Connection
                Section {
                    Button {
                        showingCreateConnection = true
                    } label: {
                        Label("Create VNC Connection", systemImage: "plus.circle")
                    }
                }

                // Settings
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("RoyalVNC")
            .onAppear {
                browser.startBrowsing()
                reloadProfiles()
            }
            .onDisappear {
                browser.stopBrowsing()
            }
            .fullScreenCover(item: $activeSession) { target in
                SessionView(hostname: target.hostname, port: target.port)
            }
            .sheet(isPresented: $showingCreateConnection) {
                CreateConnectionView(onSaved: reloadProfiles, onConnect: { host, port in
                    showingCreateConnection = false
                    activeSession = SessionTarget(hostname: host, port: port)
                })
            }
        }
    }

    private func reloadProfiles() {
        savedProfiles = ProfileStore.loadAll()
    }

    private func deleteProfiles(at offsets: IndexSet) {
        for index in offsets {
            ProfileStore.delete(savedProfiles[index])
        }
        reloadProfiles()
    }
}

struct SessionTarget: Identifiable, Hashable {
    let id = UUID()
    let hostname: String
    let port: UInt16
}

struct CreateConnectionView: View {
    var onSaved: () -> Void
    var onConnect: (String, UInt16) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "5900"
    @State private var username = ""
    @State private var password = ""

    private var portValue: UInt16 { UInt16(port) ?? 5900 }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server")) {
                    TextField("Display Name", text: $name)
                    TextField("Hostname or IP", text: $hostname)
                    TextField("Port", text: $port)
                }

                Section(header: Text("Authentication")) {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                }

                Section {
                    Button("Save Profile") {
                        let profile = ServerProfile(
                            name: name.isEmpty ? hostname : name,
                            hostname: hostname,
                            port: portValue
                        )
                        ProfileStore.add(profile)
                        if !password.isEmpty {
                            CredentialStore.save(host: hostname, port: portValue, username: username, password: password)
                        }
                        onSaved()
                        dismiss()
                    }
                    .disabled(hostname.isEmpty)

                    Button("Connect") {
                        if !password.isEmpty {
                            CredentialStore.save(host: hostname, port: portValue, username: username, password: password)
                        }
                        onConnect(hostname, portValue)
                    }
                    .disabled(hostname.isEmpty)
                }
            }
            .navigationTitle("New Connection")
        }
    }
}
#endif
