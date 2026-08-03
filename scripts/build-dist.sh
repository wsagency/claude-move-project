#!/usr/bin/env bash
#
# build-dist.sh - Build release artifacts for clamp into dist/
#
# Produces:
#   dist/clamp-<version>.tar.gz   Source tarball (clamp, LICENSE, README.md)
#   dist/clamp                    Raw script, used by install.sh
#   dist/clamp_<version>_all.deb  Debian package (requires dpkg-deb)
#   dist/clamp.rb                 Homebrew formula pinned to this release
#   dist/PKGBUILD                 AUR package build file pinned to this release
#   dist/checksums.txt            SHA-256 checksums of all artifacts
#
# Runs locally and in CI. Requires bash, tar and sha256sum (or shasum).
# dpkg-deb is optional: the .deb is skipped with a warning when missing.
#
# Usage: scripts/build-dist.sh

set -euo pipefail

REPO_SLUG="${CLAMP_REPO:-wsagency/claude-move-project}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

VERSION=$(grep -m1 '^VERSION=' "$ROOT_DIR/clamp" | cut -d'"' -f2 || true)
if [[ -z "$VERSION" ]]; then
    echo "Error: could not read VERSION from clamp" >&2
    exit 1
fi

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

echo "Building clamp $VERSION artifacts in dist/"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Source tarball with a conventional top-level directory
STAGE="$DIST_DIR/clamp-$VERSION"
mkdir -p "$STAGE"
cp "$ROOT_DIR/clamp" "$ROOT_DIR/LICENSE" "$ROOT_DIR/README.md" "$STAGE/"
chmod 755 "$STAGE/clamp"
tar -czf "$DIST_DIR/clamp-$VERSION.tar.gz" -C "$DIST_DIR" "clamp-$VERSION"
rm -rf "$STAGE"

# Raw script for curl-based installs
cp "$ROOT_DIR/clamp" "$DIST_DIR/clamp"
chmod 755 "$DIST_DIR/clamp"

TARBALL_SHA=$(sha256 "$DIST_DIR/clamp-$VERSION.tar.gz")

# Render packaging templates ({{VERSION}}, {{SHA256}}, {{REPO}}),
# dropping template-only comment lines marked with #tmpl#
render() {
    sed -e '/^#tmpl#/d' \
        -e "s/{{VERSION}}/$VERSION/g" \
        -e "s/{{SHA256}}/$TARBALL_SHA/g" \
        -e "s|{{REPO}}|$REPO_SLUG|g" \
        "$1" > "$2"
}
render "$ROOT_DIR/packaging/clamp.rb.tmpl" "$DIST_DIR/clamp.rb"
render "$ROOT_DIR/packaging/PKGBUILD.tmpl" "$DIST_DIR/PKGBUILD"

# Debian package
if command -v dpkg-deb >/dev/null 2>&1; then
    PKGROOT="$DIST_DIR/debroot"
    mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT/usr/bin" "$PKGROOT/usr/share/doc/clamp"
    cp "$ROOT_DIR/clamp" "$PKGROOT/usr/bin/clamp"
    chmod 755 "$PKGROOT/usr/bin/clamp"
    cp "$ROOT_DIR/LICENSE" "$PKGROOT/usr/share/doc/clamp/copyright"
    cat > "$PKGROOT/DEBIAN/control" <<EOF
Package: clamp
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: bash
Maintainer: Kristijan Lukačin <kristijan@gmail.com>
Homepage: https://github.com/$REPO_SLUG
Description: Move Claude Code projects while preserving session history
 clamp moves, fixes, lists, verifies, prunes and packs Claude Code
 projects while keeping session history and settings intact.
EOF
    dpkg-deb --build --root-owner-group "$PKGROOT" "$DIST_DIR/clamp_${VERSION}_all.deb" >/dev/null
    rm -rf "$PKGROOT"
else
    echo "Warning: dpkg-deb not found, skipping .deb build" >&2
fi

# Checksums for everything in dist/
(
    cd "$DIST_DIR"
    files=(clamp "clamp-$VERSION.tar.gz" clamp.rb PKGBUILD)
    [[ -f "clamp_${VERSION}_all.deb" ]] && files+=("clamp_${VERSION}_all.deb")
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${files[@]}" > checksums.txt
    else
        shasum -a 256 "${files[@]}" > checksums.txt
    fi
)

echo "Done:"
ls -l "$DIST_DIR"
