#if os(tvOS)
import SwiftUI

@main
struct RoyalVNCTVApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectView()
        }
    }
}
#else
@main
struct RoyalVNCTVApp {
    static func main() {}
}
#endif
