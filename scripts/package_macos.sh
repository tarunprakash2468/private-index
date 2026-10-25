#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# package_macos.sh — Build & package macOS release distribution assets
# Outputs:
#   1. dist/private-index-cli-<version>-darwin-arm64.tar.gz
#   2. dist/PrivateIndexMac-<version>.dmg
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo "1.0.0")}"
VERSION="${VERSION#v}" # strip leading 'v' if present

echo "==> Packaging macOS release for version: ${VERSION}"

DIST_DIR="${REPO_ROOT}/dist"
mkdir -p "${DIST_DIR}"

TMP_BUILD="/tmp/private-index-release-build"
TMP_MAC_BUILD="/tmp/private-index-mac-release-build"
rm -rf "${TMP_BUILD}" "${TMP_MAC_BUILD}"

# -----------------------------------------------------------------------------
# 1. Build & Package Developer CLI (private-index-cli)
# -----------------------------------------------------------------------------
echo "==> [1/2] Compiling private-index-cli in release mode..."
cd "${REPO_ROOT}/Packages/PrivateIndexEngine"
swift build -c release --product private-index-cli --scratch-path "${TMP_BUILD}"

CLI_BIN="${TMP_BUILD}/arm64-apple-macosx/release/private-index-cli"
if [[ ! -f "${CLI_BIN}" ]]; then
    CLI_BIN="${TMP_BUILD}/release/private-index-cli"
fi

if [[ ! -f "${CLI_BIN}" ]]; then
    echo "Error: CLI binary not found at ${CLI_BIN}"
    exit 1
fi

CLI_TARBALL="${DIST_DIR}/private-index-cli-${VERSION}-darwin-arm64.tar.gz"
echo "==> Archiving CLI to ${CLI_TARBALL}..."
CLI_STAGE="/tmp/private-index-cli-stage"
rm -rf "${CLI_STAGE}"
mkdir -p "${CLI_STAGE}"
cp "${CLI_BIN}" "${CLI_STAGE}/private-index-cli"
chmod +x "${CLI_STAGE}/private-index-cli"
ln -sf "private-index-cli" "${CLI_STAGE}/pi"
ln -sf "private-index-cli" "${CLI_STAGE}/private-index"
cp "${REPO_ROOT}/LICENSE" "${CLI_STAGE}/LICENSE"
cp -R "${REPO_ROOT}/completions" "${CLI_STAGE}/completions"

# Bundle compiled Core ML model into CLI stage if present
MODEL_SOURCE="${REPO_ROOT}/Packages/PrivateIndexEngine/Sources/PrivateIndexEngine/Resources/all-MiniLM-L6-v2.mlmodelc"
if [[ -d "${MODEL_SOURCE}" ]]; then
    mkdir -p "${CLI_STAGE}/models"
    cp -R "${MODEL_SOURCE}" "${CLI_STAGE}/models/all-MiniLM-L6-v2.mlmodelc"
    tar -czvf "${CLI_TARBALL}" -C "${CLI_STAGE}" pi private-index private-index-cli LICENSE completions models
else
    tar -czvf "${CLI_TARBALL}" -C "${CLI_STAGE}" pi private-index private-index-cli LICENSE completions
fi
rm -rf "${CLI_STAGE}"

# -----------------------------------------------------------------------------
# 2. Build & Package macOS Application (.dmg)
# -----------------------------------------------------------------------------
echo "==> [2/2] Compiling PrivateIndexMac in release mode..."
cd "${REPO_ROOT}/Apps/macOS"
swift build -c release --scratch-path "${TMP_MAC_BUILD}"

MAC_BIN="${TMP_MAC_BUILD}/arm64-apple-macosx/release/PrivateIndexMac"
if [[ ! -f "${MAC_BIN}" ]]; then
    MAC_BIN="${TMP_MAC_BUILD}/release/PrivateIndexMac"
fi

if [[ ! -f "${MAC_BIN}" ]]; then
    echo "Error: macOS binary not found at ${MAC_BIN}"
    exit 1
fi

APP_DIR="/tmp/PrivateIndexMac.app"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${MAC_BIN}" "${APP_DIR}/Contents/MacOS/PrivateIndexMac"
chmod +x "${APP_DIR}/Contents/MacOS/PrivateIndexMac"

# Inject Info.plist with release version
sed "s/1.0.0/${VERSION}/g" "${REPO_ROOT}/Apps/macOS/Info.plist" > "${APP_DIR}/Contents/Info.plist"

# Copy vocabulary bundle into Resources if present
if [[ -d "${TMP_MAC_BUILD}/arm64-apple-macosx/release/PrivateIndexEngine_PrivateIndexEngine.bundle" ]]; then
    cp -R "${TMP_MAC_BUILD}/arm64-apple-macosx/release/PrivateIndexEngine_PrivateIndexEngine.bundle" "${APP_DIR}/Contents/Resources/"
fi

# Copy compiled Core ML model into Resources if present
if [[ -d "${REPO_ROOT}/Packages/PrivateIndexEngine/Sources/PrivateIndexEngine/Resources/all-MiniLM-L6-v2.mlmodelc" ]]; then
    cp -R "${REPO_ROOT}/Packages/PrivateIndexEngine/Sources/PrivateIndexEngine/Resources/all-MiniLM-L6-v2.mlmodelc" "${APP_DIR}/Contents/Resources/"
fi

# Copy AppIcon.icns into Resources
if [[ -f "${REPO_ROOT}/Apps/macOS/Resources/AppIcon.icns" ]]; then
    cp "${REPO_ROOT}/Apps/macOS/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# Build .dmg disk image with /Applications symlink
DMG_STAGE="/tmp/dmg-stage"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${APP_DIR}" "${DMG_STAGE}/Private Index.app"
ln -s /Applications "${DMG_STAGE}/Applications"

# Set DMG volume icon if AppIcon.icns is present
if [[ -f "${REPO_ROOT}/Apps/macOS/Resources/AppIcon.icns" ]]; then
    cp "${REPO_ROOT}/Apps/macOS/Resources/AppIcon.icns" "${DMG_STAGE}/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -a C "${DMG_STAGE}" || true
    fi
fi

DMG_OUTPUT="${DIST_DIR}/PrivateIndexMac-${VERSION}.dmg"
rm -f "${DMG_OUTPUT}"

echo "==> Creating DMG disk image: ${DMG_OUTPUT}..."
hdiutil create \
    -volname "Private Index" \
    -srcfolder "${DMG_STAGE}" \
    -ov \
    -format UDZO \
    "${DMG_OUTPUT}"

rm -rf "${DMG_STAGE}" "${APP_DIR}"

echo ""
echo "==> Updating Homebrew Tap Formula..."
"${SCRIPT_DIR}/update_homebrew_formula.sh" "${VERSION}"

echo ""
echo "==> macOS release artifacts created successfully:"
ls -lh "${DIST_DIR}"
