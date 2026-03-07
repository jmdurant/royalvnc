import SwiftUI

struct CreateConnectionView: View {
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "5900"
    @State private var username = ""
    @State private var password = ""
    @State private var navigateToSession = false

    private var portValue: UInt16 {
        UInt16(port) ?? 5900
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Display Name", text: $name)

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
                Button("Save Profile") {
                    saveProfile()
                }
                .disabled(hostname.isEmpty)

                NavigationLink(isActive: $navigateToSession) {
                    SessionView(
                        hostname: hostname,
                        port: portValue
                    )
                } label: {
                    Text("Connect")
                }
                .disabled(hostname.isEmpty)
            }
        }
        .navigationTitle("New Connection")
        .onChange(of: hostname) { newValue in
            if name.isEmpty || name == previousHostname(newValue) {
                name = newValue
            }
        }
    }

    private func saveProfile() {
        let profile = ServerProfile(
            name: name.isEmpty ? hostname : name,
            hostname: hostname,
            port: portValue
        )
        ProfileStore.add(profile)

        // Save credentials if provided
        if !password.isEmpty {
            CredentialStore.save(
                host: hostname,
                port: portValue,
                username: username,
                password: password
            )
        }

        onSaved()
        dismiss()
    }

    private func previousHostname(_ current: String) -> String {
        // When hostname changes character by character, the name tracks it
        // unless the user has manually edited the name
        String(current.dropLast())
    }
}
