#if os(iOS)
import SwiftUI
import RoyalVNCKit

struct ConnectView: View {
    @StateObject private var browser = BonjourBrowser()
    @State private var savedProfiles: [ServerProfile] = []

    var body: some View {
        NavigationStack {
            List {
                // Nearby Servers (Bonjour)
                if !browser.servers.isEmpty {
                    Section("Nearby Servers") {
                        ForEach(browser.servers) { server in
                            NavigationLink {
                                SessionView(hostname: server.host, port: server.port)
                            } label: {
                                HStack {
                                    Image(systemName: "display")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(server.name)
                                            .font(.body)
                                        Text("\(server.host):\(server.port)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else if browser.isSearching {
                    Section("Nearby Servers") {
                        HStack {
                            ProgressView()
                            Text("Searching...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Saved Profiles
                if !savedProfiles.isEmpty {
                    Section("Saved") {
                        ForEach(savedProfiles) { profile in
                            NavigationLink {
                                SessionView(hostname: profile.hostname, port: profile.port)
                            } label: {
                                HStack {
                                    Image(systemName: "bookmark.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(profile.name)
                                            .font(.body)
                                        Text("\(profile.hostname):\(profile.port)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteProfiles)
                    }
                }

                // Create New Connection
                Section {
                    NavigationLink {
                        CreateConnectionView(onSaved: reloadProfiles)
                    } label: {
                        Label("Create VNC Connection", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("RoyalVNC")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onAppear {
                browser.startBrowsing()
                reloadProfiles()
            }
            .onDisappear {
                browser.stopBrowsing()
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

// MARK: - Create Connection

struct CreateConnectionView: View {
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "5900"
    @State private var username = ""
    @State private var password = ""
    @State private var navigateToSession = false

    private var portValue: UInt16 { UInt16(port) ?? 5900 }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Display Name", text: $name)
                TextField("Hostname or IP", text: $hostname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
            }

            Section("Authentication") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }

            Section {
                Button("Save Profile") {
                    saveProfile()
                }
                .disabled(hostname.isEmpty)

                NavigationLink(isActive: $navigateToSession) {
                    SessionView(hostname: hostname, port: portValue)
                } label: {
                    Text("Connect")
                }
                .disabled(hostname.isEmpty)
            }
        }
        .navigationTitle("New Connection")
    }

    private func saveProfile() {
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
}
#endif
