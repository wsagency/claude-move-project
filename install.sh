#!/usr/bin/env bash
#
# install.sh - Install clamp from GitHub Releases.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/brunos3d/claude-move-project/main/install.sh | bash
#
# Environment variables:
#   CLAMP_VERSION  Version to install without the leading v (default: latest)
#   CLAMP_BIN_DIR  Install directory (default: /usr/local/bin if writable,
#                  otherwise ~/.local/bin)
#   CLAMP_REPO     GitHub owner/repo to download from
#                  (default: brunos3d/claude-move-project)

set -euo pipefail

REPO="${CLAMP_REPO:-brunos3d/claude-move-project}"
VERSION="${CLAMP_VERSION:-latest}"

if [[ "$VERSION" == "latest" ]]; then
    BASE_URL="https://github.com/$REPO/releases/latest/download"
else
    BASE_URL="https://github.com/$REPO/releases/download/v$VERSION"
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading clamp ($VERSION) from $REPO..."
curl -fsSL "$BASE_URL/clamp" -o "$TMP_DIR/clamp"
curl -fsSL "$BASE_URL/checksums.txt" -o "$TMP_DIR/checksums.txt"

echo "Verifying checksum..."
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$TMP_DIR/clamp" | cut -d' ' -f1)
else
    actual=$(shasum -a 256 "$TMP_DIR/clamp" | cut -d' ' -f1)
fi
expected=$(grep -E '  clamp$' "$TMP_DIR/checksums.txt" | cut -d' ' -f1 || true)
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    echo "Error: checksum mismatch (expected: ${expected:-none}, got: $actual)" >&2
    echo "Aborting install." >&2
    exit 1
fi

if [[ -n "${CLAMP_BIN_DIR:-}" ]]; then
    BIN_DIR="$CLAMP_BIN_DIR"
    mkdir -p "$BIN_DIR"
elif [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
    BIN_DIR="/usr/local/bin"
else
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
fi

install -m 0755 "$TMP_DIR/clamp" "$BIN_DIR/clamp"
echo "Installed $("$BIN_DIR/clamp" --version) to $BIN_DIR/clamp"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo
        echo "Note: $BIN_DIR is not in your PATH. Add this to your shell profile:"
        echo "  export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac
