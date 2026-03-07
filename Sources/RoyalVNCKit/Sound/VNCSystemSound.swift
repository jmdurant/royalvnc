#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if os(iOS)
import AVFoundation
#elseif os(macOS)
import AppKit
#elseif os(watchOS)
import WatchKit
#endif

struct VNCSystemSound { }

extension VNCSystemSound {
	func play() {
#if os(macOS)
        NSSound.beep()
#elseif os(iOS)
        // With vibration
        let systemSoundID: SystemSoundID = 1013

        AudioServicesPlaySystemSound(systemSoundID)
#elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
#else
        // TODO: Implement beep on Linux/Windows/etc.
#endif
	}
}
