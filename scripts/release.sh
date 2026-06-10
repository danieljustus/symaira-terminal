#!/bin/bash
set -euo pipefail

# Symaira Terminal - Release Script
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.0.0

VERSION="${1:?Usage: $0 <version>}"
APP_NAME="SymairaTerminal"
SCHEME="SymairaTerminal"
BUILD_DIR="build/release"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
IPA_PATH="${BUILD_DIR}/${APP_NAME}.ipa"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "=== Building ${APP_NAME} ${VERSION} ==="

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

xcodegen generate

echo "Archiving..."
xcodebuild archive \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -archivePath "${ARCHIVE_PATH}" \
    -configuration Release \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO

echo "Exporting..."
cat > "${BUILD_DIR}/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
    -exportPath "${EXPORT_PATH}"

echo "Notarizing..."
APP_PATH=$(find "${EXPORT_PATH}" -name "*.app" -type d | head -1)
if [ -z "${APP_PATH}" ]; then
    echo "Error: No .app found in export path"
    exit 1
fi

xcrun notarytool submit "${APP_PATH}" \
    --keychain-profile "notarytool" \
    --wait

xcrun stapler staple "${APP_PATH}"

echo "Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${APP_PATH}" \
    -ov -format UDZO \
    "${DMG_PATH}"

echo "Uploading to GitHub..."
gh release create "v${VERSION}" \
    "${DMG_PATH}#${APP_NAME}-${VERSION}.dmg" \
    --title "v${VERSION}" \
    --notes "Release ${VERSION}"

echo "Updating Homebrew tap..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/update-homebrew-tap.sh" "${VERSION}" "${DMG_PATH}" || {
    echo "Warning: Homebrew tap update failed. Run manually:"
    echo "  ${SCRIPT_DIR}/update-homebrew-tap.sh ${VERSION} ${DMG_PATH}"
}

echo "=== Release ${VERSION} complete ==="
