#!/usr/bin/env bash
# Keep SDK installation, native compilation and published runtime metadata aligned.
: "${SWIFT_ANDROID_VERSION:=6.2.3}"
: "${ANDROID_API_LEVEL:=29}"
: "${SWIFT_ANDROID_ROOT:=${HOME}/Library/org.swift.swiftpm/swift-sdks/swift-${SWIFT_ANDROID_VERSION}-RELEASE_android.artifactbundle/swift-android}"
