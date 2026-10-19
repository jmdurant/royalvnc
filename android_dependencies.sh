#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/android-toolchain.sh"

echo "Installing Skip using Homebrew"
brew install skiptools/skip/skip

echo "Installing Swift Android SDK $SWIFT_ANDROID_VERSION"
SWIFT_ANDROID_SDK_HOME="$(dirname "$(dirname "$SWIFT_ANDROID_ROOT")")"
mkdir -p "$SWIFT_ANDROID_SDK_HOME"
SWIFT_ANDROID_SDK_HOME="$(cd "$SWIFT_ANDROID_SDK_HOME" && pwd -P)"
skip android sdk install --version "$SWIFT_ANDROID_VERSION" --swift-sdk-home "$SWIFT_ANDROID_SDK_HOME"

echo "All Done"
