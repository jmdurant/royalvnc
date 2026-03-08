#if os(watchOS)
import SwiftUI

@main
struct RoyalVNCWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectView()
        }
    }
}
#else
@main
struct RoyalVNCWatchApp {
    static func main() {}
}
#endif
