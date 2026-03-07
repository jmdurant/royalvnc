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
                                SessionView(
                                    hostname: server.host,
                                    port: server.port
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

                // Saved Profiles
                if !savedProfiles.isEmpty {
                    Section("Saved") {
                        ForEach(savedProfiles) { profile in
                            NavigationLink {
                                SessionView(
                                    hostname: profile.hostname,
                                    port: profile.port
                                )
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .font(.body)
                                    Text("\(profile.hostname):\(profile.port)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
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
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }

                        NavigationLink {
                            ControlsInfoView()
                        } label: {
                            Image(systemName: "info.circle")
                        }
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
