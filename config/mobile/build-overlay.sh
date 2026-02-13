#!/bin/bash
set -euo pipefail
#
# Build the EthernetOverlay APK for the iran-mobile (redroid) node.
#
# Prerequisites (installed in .devcontainer/Dockerfile):
#   - Android SDK build-tools (aapt2, apksigner)
#   - Android platform android-34 (framework-res.apk for resource linking)
#   - Java 17+ (required by apksigner)
#
# Source files:
#   config/mobile/src/AndroidManifest.xml
#   config/mobile/src/res/values/config.xml
#
# Output:
#   config/mobile/EthernetOverlayReproducible.apk
#
# Usage:
#   ./config/mobile/build-overlay.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
OUT_APK="${SCRIPT_DIR}/EthernetOverlayReproducible.apk"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "${BUILD_DIR}"' EXIT

ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
BUILD_TOOLS="${ANDROID_HOME}/build-tools/35.0.0"
AAPT2="${BUILD_TOOLS}/aapt2"
ZIPALIGN="${BUILD_TOOLS}/zipalign"
APKSIGNER="${BUILD_TOOLS}/apksigner"
FRAMEWORK="${ANDROID_HOME}/platforms/android-34/android.jar"

for tool in "$AAPT2" "$ZIPALIGN" "$APKSIGNER" "$FRAMEWORK"; do
    if [ ! -f "$tool" ]; then
        echo "ERROR: $tool not found. Install Android SDK build-tools and platform android-34." >&2
        echo "  sdkmanager 'build-tools;35.0.0' 'platforms;android-34'" >&2
        exit 1
    fi
done

echo "==> Compiling resources..."
"$AAPT2" compile --dir "${SRC_DIR}/res" -o "${BUILD_DIR}/compiled.zip"

echo "==> Linking APK..."
"$AAPT2" link \
    --manifest "${SRC_DIR}/AndroidManifest.xml" \
    -I "$FRAMEWORK" \
    -o "${BUILD_DIR}/overlay-unaligned.apk" \
    "${BUILD_DIR}/compiled.zip"

echo "==> Zipaligning (4-byte boundary for resources.arsc)..."
"$ZIPALIGN" -f -p 4 "${BUILD_DIR}/overlay-unaligned.apk" "${BUILD_DIR}/overlay-unsigned.apk"

echo "==> Generating signing key..."
KEYSTORE="${BUILD_DIR}/debug.keystore"
keytool -genkeypair \
    -keystore "$KEYSTORE" \
    -storepass android \
    -keypass android \
    -alias overlay \
    -keyalg RSA \
    -keysize 2048 \
    -validity 36500 \
    -dname "CN=IranFilteringLab" \
    -storetype PKCS12 \
    2>/dev/null

echo "==> Signing APK (v1 + v2)..."
"$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:android \
    --key-pass pass:android \
    --ks-key-alias overlay \
    --v1-signing-enabled true \
    --v2-signing-enabled true \
    --out "$OUT_APK" \
    "${BUILD_DIR}/overlay-unsigned.apk"

echo "==> Verifying..."
"$APKSIGNER" verify --verbose "$OUT_APK" 2>&1 | head -5
"$ZIPALIGN" -c -v 4 "$OUT_APK" 2>&1 | tail -1

SIZE=$(stat -c%s "$OUT_APK")
echo "==> Built: ${OUT_APK} (${SIZE} bytes)"
