#!/usr/bin/env bash
# install.sh — Install symterm to /usr/local/bin
#
# Usage (from repo root):
#   bash scripts/install.sh
#   bash scripts/install.sh --uninstall
#
# Requires write access to /usr/local/bin (sudo or pre-created by Homebrew on Apple Silicon).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMTERM_SRC="${SCRIPT_DIR}/symterm"
INSTALL_DIR="${SYMTERM_INSTALL_DIR:-/usr/local/bin}"
INSTALL_PATH="${INSTALL_DIR}/symterm"

die() {
    echo "install.sh: $*" >&2
    exit 1
}

uninstall() {
    if [ -L "$INSTALL_PATH" ] || [ -f "$INSTALL_PATH" ]; then
        rm "$INSTALL_PATH"
        echo "Removed ${INSTALL_PATH}"
    else
        echo "symterm is not installed at ${INSTALL_PATH} — nothing to do."
    fi
}

install_symterm() {
    [ -f "$SYMTERM_SRC" ] || die "Source file not found: ${SYMTERM_SRC}"

    # Ensure /usr/local/bin exists (common on macOS with Homebrew)
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "Creating ${INSTALL_DIR} (requires sudo)..."
        sudo mkdir -p "$INSTALL_DIR"
    fi

    chmod +x "$SYMTERM_SRC"

    if [ -L "$INSTALL_PATH" ] && [ "$(readlink "$INSTALL_PATH")" = "$SYMTERM_SRC" ]; then
        echo "symterm is already installed at ${INSTALL_PATH} (symlink up-to-date)."
        return 0
    fi

    # Try without sudo first (works when the user owns /usr/local/bin, e.g. Homebrew on Apple Silicon)
    if ln -sf "$SYMTERM_SRC" "$INSTALL_PATH" 2>/dev/null; then
        echo "Installed: ${INSTALL_PATH} → ${SYMTERM_SRC}"
    else
        echo "Installing with sudo (write permission needed for ${INSTALL_DIR})..."
        sudo ln -sf "$SYMTERM_SRC" "$INSTALL_PATH"
        echo "Installed: ${INSTALL_PATH} → ${SYMTERM_SRC}"
    fi

    echo ""
    echo "Done! Run 'symterm --help' to get started."
}

case "${1:-}" in
    --uninstall|-u)
        uninstall
        ;;
    --help|-h)
        echo "Usage: bash scripts/install.sh [--uninstall]"
        echo ""
        echo "  (no args)     Symlink symterm to ${INSTALL_DIR}/symterm"
        echo "  --uninstall   Remove the symlink"
        echo ""
        echo "Override install directory: SYMTERM_INSTALL_DIR=/path/bin bash scripts/install.sh"
        ;;
    "")
        install_symterm
        ;;
    *)
        die "Unknown argument: $1 (try --help)"
        ;;
esac
