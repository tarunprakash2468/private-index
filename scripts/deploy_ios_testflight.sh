#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# deploy_ios_testflight.sh — Build and upload iOS App to Apple TestFlight
# Strictly routes builds to TestFlight; does not export loose .ipa files.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo "1.0.0")}"
VERSION="${VERSION#v}"

echo "==> Preparing iOS deployment for TestFlight (Version: ${VERSION})"

# Check for App Store Connect API credentials
API_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
API_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"
API_PRIVATE_KEY="${APP_STORE_CONNECT_PRIVATE_KEY:-}"

if [[ -z "${API_KEY_ID}" || -z "${API_ISSUER_ID}" || -z "${API_PRIVATE_KEY}" ]]; then
    echo "-----------------------------------------------------------------------"
    echo "ℹ TestFlight Credentials Not Configured"
    echo "To enable automated TestFlight deployment, configure these GitHub Secrets:"
    echo "  - APP_STORE_CONNECT_KEY_ID (e.g. 2X9R4HXF34)"
    echo "  - APP_STORE_CONNECT_ISSUER_ID (e.g. 57246542-96fe-1a63-e053-0824d011072a)"
    echo "  - APP_STORE_CONNECT_PRIVATE_KEY (Contents of AuthKey_<KEY_ID>.p8)"
    echo ""
    echo "Skipping TestFlight upload for this run."
    echo "-----------------------------------------------------------------------"
    exit 0
fi

TMP_IOS_BUILD="/tmp/private-index-ios-release-build"
rm -rf "${TMP_IOS_BUILD}"

echo "==> Building iOS target with iPhoneOS SDK..."
cd "${REPO_ROOT}/Apps/iOS"
IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || xcrun --sdk iphonesimulator --show-sdk-path)"

swift build -c release \
    --triple arm64-apple-ios17.0 \
    -Xswiftc -sdk -Xswiftc "${IPHONEOS_SDK}" \
    --scratch-path "${TMP_IOS_BUILD}"

# Assemble temporary IPA payload
STAGE_DIR="/tmp/testflight-stage"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/Payload/PrivateIndexIOS.app"

IOS_BIN="${TMP_IOS_BUILD}/arm64-apple-ios17.0/release/PrivateIndexIOS"
if [[ ! -f "${IOS_BIN}" ]]; then
    IOS_BIN="${TMP_IOS_BUILD}/release/PrivateIndexIOS"
fi

if [[ -f "${IOS_BIN}" ]]; then
    cp "${IOS_BIN}" "${STAGE_DIR}/Payload/PrivateIndexIOS.app/PrivateIndexIOS"
    chmod +x "${STAGE_DIR}/Payload/PrivateIndexIOS.app/PrivateIndexIOS"
fi

# Copy Info.plist
sed "s/1.0.0/${VERSION}/g" "${REPO_ROOT}/Apps/iOS/Info.plist" > "${STAGE_DIR}/Payload/PrivateIndexIOS.app/Info.plist"

IPA_PATH="/tmp/PrivateIndexIOS-${VERSION}.ipa"
rm -f "${IPA_PATH}"
cd "${STAGE_DIR}"
zip -qr "${IPA_PATH}" Payload/
rm -rf "${STAGE_DIR}"

echo "==> Setting up App Store Connect API Key..."
KEY_DIR="${HOME}/.appstoreconnect/private_keys"
mkdir -p "${KEY_DIR}"
KEY_FILE="${KEY_DIR}/AuthKey_${API_KEY_ID}.p8"
echo "${API_PRIVATE_KEY}" > "${KEY_FILE}"
chmod 600 "${KEY_FILE}"

echo "==> Uploading build ${VERSION} to Apple TestFlight..."
xcrun altool --upload-app \
    -f "${IPA_PATH}" \
    --type ios \
    --apiKey "${API_KEY_ID}" \
    --apiIssuer "${API_ISSUER_ID}"

# Clean up private key and temporary IPA immediately
rm -f "${KEY_FILE}" "${IPA_PATH}"

echo "==> ✔ Successfully submitted to Apple TestFlight!"
