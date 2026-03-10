#if os(iOS)
import SwiftUI

@main
struct RoyalVNCiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectView()
        }
    }
}
#else
@main
struct RoyalVNCiOSApp {
    static func main() {}
}
#endif
