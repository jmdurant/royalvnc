#!/usr/bin/env bash

set -e

ANDROID_API_LEVEL="29"

SWIFT_SDKS_DIR="${HOME}/Library/org.swift.swiftpm/swift-sdks"

# Dynamically locate Swift Android SDK bundle if not explicitly set
if [[ -z "${SWIFT_ANDROID_ROOT}" || ! -d "${SWIFT_ANDROID_ROOT}" ]]; then
	FOUND_ROOT=$(find "${SWIFT_SDKS_DIR}" -maxdepth 3 -type d -name "swift-android" 2>/dev/null | sort -V | tail -n 1)
	if [[ -n "${FOUND_ROOT}" && -d "${FOUND_ROOT}" ]]; then
		SWIFT_ANDROID_ROOT="${FOUND_ROOT}"
	else
		SWIFT_ANDROID_ROOT="${SWIFT_SDKS_DIR}/swift-6.2.3-RELEASE_android.artifactbundle/swift-android"
	fi
fi

echo "Using SWIFT_ANDROID_ROOT: ${SWIFT_ANDROID_ROOT}"

# Locate Swift SDK arm64 library directory
SWIFT_CORE_SO=$(find "${SWIFT_ANDROID_ROOT}" -name "libswiftCore.so" 2>/dev/null | grep -E "swift-aarch64|aarch64" | head -n 1)
if [[ -n "${SWIFT_CORE_SO}" ]]; then
	SWIFT_ANDROID_SDK_ARM64=$(dirname "${SWIFT_CORE_SO}")
else
	SWIFT_ANDROID_SDK_ARM64="${SWIFT_ANDROID_ROOT}/swift-resources/usr/lib/swift-aarch64/android"
fi

echo "Using SWIFT_ANDROID_SDK_ARM64: ${SWIFT_ANDROID_SDK_ARM64}"

# Locate libc++_shared.so across Swift Android SDK or installed Android NDKs
LIBCXX_SHARED_SO=$(find "${SWIFT_ANDROID_ROOT}" \
	"${ANDROID_NDK_HOME}" \
	"${ANDROID_HOME}/ndk" \
	"${ANDROID_HOME}/ndk-bundle" \
	"${HOME}/Library/Android/sdk/ndk" \
	2>/dev/null | grep -E "aarch64|arm64-v8a" | grep "libc\+\+_shared\.so" | head -n 1)

if [[ -z "${LIBCXX_SHARED_SO}" || ! -f "${LIBCXX_SHARED_SO}" ]]; then
	LIBCXX_SHARED_SO="${SWIFT_ANDROID_ROOT}/ndk-sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
fi

echo "Using libc++_shared.so: ${LIBCXX_SHARED_SO}"

KOTLIN_PROJECT_DIR="Bindings/kotlin/RoyalVNCAndroidTest"

declare -a SWIFT_RUNTIME_LIBS=(
	# NDK C++
	"${LIBCXX_SHARED_SO}"

	# Swift SDK for Android
	"${SWIFT_ANDROID_SDK_ARM64}/libBlocksRuntime.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libdispatch.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libFoundationEssentials.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswift_Builtin_float.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswift_Concurrency.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswift_math.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswift_RegexParser.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswift_StringProcessing.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswiftAndroid.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswiftCore.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswiftDispatch.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswiftRegexBuilder.so"
	"${SWIFT_ANDROID_SDK_ARM64}/libswiftSynchronization.so"
)

echo "Building RoyalVNC for Android"
skip android build \
	--configuration release \
	--no-bridge \
	--android-api-level ${ANDROID_API_LEVEL} \
	--arch aarch64

# royalvnc module
ROYALVNC_JNILIBS_DIR="${KOTLIN_PROJECT_DIR}/royalvnc/src/main/jniLibs/arm64-v8a"

echo "Cleaning royalvnc JNI libraries"
mkdir -p "${ROYALVNC_JNILIBS_DIR}"
rm -f "${ROYALVNC_JNILIBS_DIR}"/*.so

echo "Copying RoyalVNC library"
BUILT_LIB=$(find .build -name "libRoyalVNCKit.so" 2>/dev/null | grep "aarch64" | grep "release" | head -n 1)
if [[ -z "${BUILT_LIB}" || ! -f "${BUILT_LIB}" ]]; then
	BUILT_LIB=".build/aarch64-unknown-linux-android${ANDROID_API_LEVEL}/release/libRoyalVNCKit.so"
fi
cp -f "${BUILT_LIB}" "${ROYALVNC_JNILIBS_DIR}/"

echo "Building royalvnc.aar Maven bundle"
pushd "${KOTLIN_PROJECT_DIR}"
./gradlew :royalvnc:publishMavenBundle
popd

ROYALVNC_BUNDLE_FILE="${KOTLIN_PROJECT_DIR}/royalvnc/build/distributions/royalvnc.zip"
if [[ -f "${ROYALVNC_BUNDLE_FILE}" ]]; then
	echo "Found ${ROYALVNC_BUNDLE_FILE}"
else
	echo "Error: cannot find ${ROYALVNC_BUNDLE_FILE}"
	exit 1
fi

# swiftRuntime module
SWIFTRUNTIME_JNILIBS_DIR="${KOTLIN_PROJECT_DIR}/swiftRuntime/src/main/jniLibs/arm64-v8a"

echo "Cleaning swiftRuntime JNI libraries"
mkdir -p "${SWIFTRUNTIME_JNILIBS_DIR}"
rm -f "${SWIFTRUNTIME_JNILIBS_DIR}"/*.so

echo "Copying Swift runtime libraries"
for swiftRuntime_lib in "${SWIFT_RUNTIME_LIBS[@]}"
do
	if [[ -f "${swiftRuntime_lib}" ]]; then
		cp -f "${swiftRuntime_lib}" "${SWIFTRUNTIME_JNILIBS_DIR}/"
	else
		echo "Warning: runtime library not found: ${swiftRuntime_lib}"
	fi
done

echo "Swift version"
SWIFT_VERSION=$(swift --version)

if [[ "${SWIFT_VERSION}" =~ Swift\ version\ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
	SWIFT_RT_VERSION="${BASH_REMATCH[1]}"
	echo "SWIFT_RT_VERSION detected: ${SWIFT_RT_VERSION}"
else
	echo "Cannot parse SWIFT_VERSION: ${SWIFT_VERSION}"
	exit 1
fi

echo "Building swiftRuntime.aar Maven bundle"
pushd "${KOTLIN_PROJECT_DIR}"
SWIFT_RT_VERSION=$SWIFT_RT_VERSION ./gradlew :swiftRuntime:publishMavenBundle
popd

SWIFTRUNTIME_BUNDLE_FILE="${KOTLIN_PROJECT_DIR}/swiftRuntime/build/distributions/swiftRuntime_android.zip"
if [[ -f "${SWIFTRUNTIME_BUNDLE_FILE}" ]]; then
	echo "Found ${SWIFTRUNTIME_BUNDLE_FILE}"
else
	echo "Error: cannot find ${SWIFTRUNTIME_BUNDLE_FILE}"
	exit 1
fi

echo "All Done - Open Bindings/kotlin/RoyalVNCAndroidTest in Android Studio now"