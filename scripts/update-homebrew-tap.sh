#!/bin/bash
set -euo pipefail

# Usage: ./scripts/update-homebrew-tap.sh <version> <dmg-path>
# Example: ./scripts/update-homebrew-tap.sh 1.0.0 build/release/SymairaTerminal-1.0.0.dmg
#
# Prerequisites:
#   - HOMEBREW_TAP_GITHUB_TOKEN: GitHub PAT with repo scope (for pushing to the tap repo)
#   - The tap repo must exist: github.com/danieljustus/homebrew-tap

VERSION="${1:?Usage: $0 <version> <dmg-path>}"
DMG_PATH="${2:?Usage: $0 <version> <dmg-path>}"

TAP_REPO="danieljustus/homebrew-tap"
TAP_REPO_URL="https://github.com/${TAP_REPO}.git"
CASK_NAME="symterminal"
CASK_FILE="Casks/${CASK_NAME}.rb"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -f "${DMG_PATH}" ]; then
    echo "Error: DMG not found at ${DMG_PATH}"
    exit 1
fi

echo "Computing SHA256 of DMG..."
SHA256=$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')
echo "SHA256: ${SHA256}"

TAP_DIR="$(mktemp -d)/homebrew-tap"
echo "Cloning tap repo..."
if [ -n "${HOMEBREW_TAP_GITHUB_TOKEN:-}" ]; then
    git clone "https://x-access-token:${HOMEBREW_TAP_GITHUB_TOKEN}@github.com/${TAP_REPO}.git" "${TAP_DIR}"
else
    git clone "${TAP_REPO_URL}" "${TAP_DIR}"
fi

cd "${TAP_DIR}"
mkdir -p Casks

cat > "${CASK_FILE}" << EOF
cask "${CASK_NAME}" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/danieljustus/symaira-terminal/releases/download/v#{version}/SymairaTerminal-#{version}.dmg"
  name "Symaira Terminal"
  desc "Native macOS terminal built for the Human-AI era"
  homepage "https://github.com/danieljustus/symaira-terminal"

  livecheck do
    url "https://github.com/danieljustus/symaira-terminal/releases/latest"
    strategy :header_match
    regex(/SymairaTerminal-(\\d+(?:\\.\\d+)*)\\.dmg/i)
  end

  depends_on macos: :sonoma

  app "SymairaTerminal.app"

  zap trash: [
    "~/Library/Application Support/SymairaTerminal",
    "~/Library/Preferences/com.symaira.terminal.plist",
    "~/Library/Caches/com.symaira.terminal",
  ]
end
EOF

echo "Updated Cask file:"
cat "${CASK_FILE}"

# Keep the repo's own copy in sync so it never drifts from the tap
# (it used to carry a PLACEHOLDER_SHA256).
cp "${CASK_FILE}" "${REPO_ROOT}/Casks/${CASK_NAME}.rb"

git add "${CASK_FILE}"
git -c user.name="Symaira Bot" -c user.email="bot@symaira.dev" \
    commit -m "Update ${CASK_NAME} to v${VERSION}"
git push origin main

echo "=== Homebrew tap updated: ${CASK_NAME} v${VERSION} (SHA256: ${SHA256}) ==="
rm -rf "${TAP_DIR}"
