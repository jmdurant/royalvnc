[![CI](https://github.com/royalapplications/royalvnc/actions/workflows/ci.yml/badge.svg)](https://github.com/royalapplications/royalvnc/actions/workflows/ci.yml)

![RoyalVNC](Design/Banner_Rendered/Banner.png)

RoyalVNC is a modern, high performance implementation of the [VNC/RFB protocol](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst) written in Swift.
The SDK (RoyalVNCKit) is compatible with Swift, Objective-C, C, C# and Kotlin on macOS, iOS, iPadOS, tvOS, watchOS, Android, Linux and Windows.
It depends on [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift), [zlib](https://github.com/madler/zlib) and D3DES (see [Credits](#Credits)).

## Supported Features

### Security Types (Authentication Methods)
- No Authentication
- VNC Password
- Apple Remote Desktop
- UltraVNC MS-Logon II

### Encodings
- Tight
- Zlib
- ZRLE
- Hextile
- CoRRE
- RRE
- CopyRect

### Pseudo Encodings
- LastRect
- CompressionLevel
- JpegCompressionLevel
- DesktopName
- Cursor
- DesktopSize
- ExtendedDesktopSize
- ContinuousUpdates

### Misc. Features
- Support for 8-bit, 16-bit and 24/32-bit color depths with high-performance framebuffer implementations.
- Clipboard redirection support for text in both ways (remote to local and local to remote).
- Connection state management and rendering is decoupled from each other, so it's possible to build "headless" clients (ie. no rendering of the remote desktop).
- The SDK includes a ready-to-use implementation of a framebuffer view for macOS (subclass of `NSView`), which also handles mouse and keyboard input, local cursor (`NSCursor`), scaling and rendering. The iOS/iPadOS equivalent (`UIView`) is a work-in-progress.
- First-class error handling. The `VNCError` type divides all possible errors into three broad categories: Protocol, Authentication and Connection errors. There are helper functions to retrieve human-readable descriptions for all errors and a convenience functions that allows the SDK consumer to distinguish between errors that should be displayed to the user and ones that shouldn't.
- Headless CLI demos (one using Swift and another one using the C API) are included in the repository.
- The repository also contains C# bindings so the library can be used with .NET.
- Kotlin bindings and Android phone/tablet/TV demo clients are included under `Bindings/kotlin/RoyalVNCAndroidTest`.
- SwiftUI demo clients for iOS/iPadOS, tvOS and watchOS are included in this repository. They share discovery, profiles, authentication and session handling through `RoyalVNCClientCore`.
- [The separate demo repository](https://github.com/royalapplications/royalvnc-demo) also contains macOS Swift and Objective-C clients.

## Platform support and builds

The SDK and demo apps have different deployment targets. These are development/demo clients; store signing, provisioning and distribution are configured separately.

| Platform | SDK minimum | Included client / build |
| --- | --- | --- |
| macOS | 11 | Swift and C command-line demos; AppKit framebuffer view |
| iOS / iPadOS | 15 | SwiftUI app in `iOSApp`, minimum 16 |
| tvOS | 15 | SwiftUI app in `TVApp`, minimum 16 |
| watchOS | 10 | Standalone SwiftUI app in `WatchApp`, minimum 10 |
| Android / Android TV | API 29 | Compose app and Kotlin bindings; native artifacts currently `arm64-v8a` only |
| Linux / Windows | Swift toolchain supported OS | Native SDK, command-line demos and .NET bindings |
| Mac Catalyst / visionOS | 15 / 1 | Package platform declarations; no dedicated app or CI launch coverage |

### SDK and regression tests

Install Swift 6 or later (the package uses Swift 5 language mode), then run:

```sh
swift build --product RoyalVNCKit
swift test
swift run RoyalVNCKitDemo localhost
```

The tests cover socket cancellation, deadlines, fragmented reads, full writes under backpressure, decoder registration and pixel output for all advertised encodings, and credential serialization/authentication lifecycle. On Apple platforms the socket tests explicitly exercise the fallback transport used on Android/Linux/Windows rather than Network.framework.

### Apple apps

Install Xcode with the relevant platform SDKs/simulator runtimes and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Generate a project and open it:

```sh
xcodegen generate --spec iOSApp/project.yml
open iOSApp/RoyalVNCiOS.xcodeproj
```

Use `TVApp/project.yml` or `WatchApp/project.yml` for the other apps. Select your development team for device builds. The apps depend on the automatic `RoyalVNCClientCore` product, which links the VNC engine into the app; the separate dynamic `RoyalVNCKit` product remains available for SDK consumers and native bindings.

`iOSApp/Info.plist` is the version source for all three Apple apps. Update its `CFBundleShortVersionString` and `CFBundleVersion`, then regenerate the projects. XcodeGen's pre-generation step writes an ignored shared version configuration without overwriting the source plist.

To build, verify package contents/versioning, and launch each app in a simulator:

```sh
python3 scripts/apple-app-smoke.py ios
python3 scripts/apple-app-smoke.py tvos
python3 scripts/apple-app-smoke.py watchos
```

Logs, screenshots and simulator app archives are saved under `.build/apple-smoke`. Use `--skip-launch` for build/package checks when no simulator runtime is installed; this does not validate app launch.

### Android phone and TV app

Native builds currently require macOS, Homebrew, a JDK 21 installation, and the Android SDK (set `JAVA_HOME` and `ANDROID_HOME`). Install/build the matching Swift Android toolchain and native runtime before assembling the app:

```sh
./android_dependencies.sh
./android_build.sh
cd Bindings/kotlin/RoyalVNCAndroidTest
./gradlew :app:assembleDebug :app:testDebugUnitTest
./gradlew :app:connectedDebugAndroidTest
```

The connected tests require an ARM64 Android device/emulator, because the packaged native library is ARM64. They exercise real Keystore encryption and migration as well as native-library loading. The app selects the TV controls automatically on Leanback devices.

The default Swift Android version is pinned in `scripts/android-toolchain.sh`. To upgrade, pass the same `SWIFT_ANDROID_VERSION` to both installation and build commands. Runtime artifact versions come from this Android SDK version, not the host Xcode compiler. `SWIFT_ANDROID_ROOT` can override the installed SDK location. Native build output is isolated under `.build/android`.

From the repository root, `python3 scripts/android-package-smoke.py` checks that the APK includes its required ARM64 native libraries. Opening the Gradle project without first building those libraries can produce an APK that compiles but cannot create a VNC session.

### Credentials and CI

Credentials are persisted only after successful authentication. Apple apps use Keychain with versioned JSON records; Android uses AES-GCM with an Android Keystore key. Existing credentials migrate on upgrade, rejected credentials are removed, and users are prompted again on the next connection. Android credentials are excluded from cloud backup and device transfer; a restored app requires re-entry.

Pull requests and pushes to `main` run SDK builds and Swift regressions, Android app/unit/package checks, real Keystore tests on an x86_64 Android emulator, and Apple simulator build/package/launch checks. The native Android smoke test runs locally on ARM64 devices/emulators; hosted macOS ARM runners do not support the nested virtualization required by the Android emulator. Real-server interoperability, device-specific input, and store-signed release validation should also be checked before distributing a release.

## Usage
See [Usage](USAGE.md).

## License
[MIT License](LICENSE)

## Credits
- [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift) ([The CryptoSwift license](https://github.com/krzyzanowskim/CryptoSwift/blob/main/LICENSE))
- [zlib](https://github.com/madler/zlib) ([zlib license](https://github.com/madler/zlib/blob/develop/LICENSE))
- [stb](https://github.com/troughton/Cstb) ([public domain](https://github.com/troughton/Cstb/blob/main/LICENSE))
- D3DES (Public Domain, Copyright Richard Outerbridge)
