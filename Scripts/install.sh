#!/bin/sh
# EQRouter Linux installer.
#
# Downloads the latest static binary (x86-64 or ARM64) from GitHub Releases
# and installs it to /usr/local/bin (or ~/.local/bin without root). The binary
# is fully static (musl) so it runs on any Linux distro with no dependencies.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/adv4sd-cyber/eqrouter-linux/main/Scripts/install.sh | sh
#
# Options (env vars):
#   EQROUTER_VERSION=v0.1.0   install a specific release (default: latest)
#   EQROUTER_PREFIX=~/.local  install prefix (binary goes in $PREFIX/bin)

set -eu

REPO="adv4sd-cyber/eqrouter-linux"
VERSION="${EQROUTER_VERSION:-latest}"

# --- checks ---------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
if [ "$OS" != "Linux" ]; then
    echo "error: this installer is for Linux (detected: $OS)." >&2
    exit 1
fi
case "$ARCH" in
    x86_64|amd64)   ASSET="eqrouter-linux-x86_64.tar.gz" ;;
    aarch64|arm64)  ASSET="eqrouter-linux-aarch64.tar.gz" ;;
    *)
        echo "error: prebuilt binaries are x86-64 and ARM64 only (detected: $ARCH)." >&2
        echo "Build from source instead: https://github.com/$REPO#build-from-source" >&2
        exit 1
        ;;
esac

if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fSL --progress-bar -o "$1" "$2"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -qO "$1" --show-progress "$2"; }
else
    echo "error: need curl or wget." >&2
    exit 1
fi

# --- pick install dir ------------------------------------------------------
if [ -n "${EQROUTER_PREFIX:-}" ]; then
    BIN_DIR="$EQROUTER_PREFIX/bin"
    SUDO=""
elif [ "$(id -u)" = "0" ]; then
    BIN_DIR="/usr/local/bin"
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    BIN_DIR="/usr/local/bin"
    SUDO="sudo"
else
    BIN_DIR="$HOME/.local/bin"
    SUDO=""
fi

# --- download --------------------------------------------------------------
if [ "$VERSION" = "latest" ]; then
    URL="https://github.com/$REPO/releases/latest/download/$ASSET"
else
    URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading eqrouter ($VERSION) ..."
fetch "$TMP/$ASSET" "$URL"
tar -xzf "$TMP/$ASSET" -C "$TMP"

# --- install ---------------------------------------------------------------
echo "Installing to $BIN_DIR/eqrouter ..."
$SUDO mkdir -p "$BIN_DIR"
$SUDO install -m 755 "$TMP/eqrouter" "$BIN_DIR/eqrouter"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "note: $BIN_DIR is not on your PATH — add it to your shell profile." ;;
esac

echo
echo "Installed. Get started:"
echo "  eqrouter serve      # web control panel at http://127.0.0.1:8080/"
echo "  eqrouter doctor     # check runtime dependencies for live routing"
