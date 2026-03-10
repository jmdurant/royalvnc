#if os(iOS)
import SwiftUI

@main
struct RoyalVNCiOSApp: App {
    @ObservedObject private var settings = ConnectionSettings.shared

    var body: some Scene {
        WindowGroup {
            ConnectView()
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
#else
@main
struct RoyalVNCiOSApp {
    static func main() {}
}
#endif
