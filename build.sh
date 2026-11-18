#!/usr/bin/env bash
# Build a local MOS plugin .deb for OpenCode v2.
#
#   ./build.sh              # version from page/plugin.config.js
#   ./build.sh 0.1.1        # explicit version
#   SKIP_PAGE=1 ./build.sh  # reuse page/dist

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${1:-${VERSION:-}}"
if [ -z "$VERSION" ]; then
  VERSION="$(node -e "import('./page/plugin.config.js').then(m => console.log(m.default.version))" 2>/dev/null || echo 0.1.0)"
fi

PKG_NAME="opencode-v2-${VERSION}-1+mos-plugin"
PKG_DIR="$ROOT/build/${PKG_NAME}_all"
DEB_FILE="$ROOT/build/${PKG_NAME}_all.deb"
PAGE_DIST="$ROOT/page/dist/opencode-v2"

echo "==> OpenCode v2 MOS plugin ${VERSION}"

if [ "${SKIP_PAGE:-0}" != "1" ]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required to build the plugin page" >&2
    exit 1
  fi
  if [ ! -d "$ROOT/page/node_modules" ]; then
    echo "==> npm install"
    ( cd "$ROOT/page" && npm install )
  fi
  echo "==> building plugin page"
  ( cd "$ROOT/page" && PLUGIN_VERSION="$VERSION" npm run build )
fi

if [ ! -f "$PAGE_DIST/remoteEntry.js" ]; then
  echo "page build output missing: $PAGE_DIST/remoteEntry.js" >&2
  exit 1
fi

rm -rf "$ROOT/build"
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/usr/bin/plugins" \
  "$PKG_DIR/usr/share/opencode-v2-plugin" \
  "$PKG_DIR/var/www/mos-plugins/opencode-v2"

install -m 0755 "$ROOT/opencode-backend" "$PKG_DIR/usr/bin/plugins/opencode-v2"
install -m 0755 "$ROOT/opencode-wrapper" "$PKG_DIR/usr/bin/opencode"
install -m 0755 "$ROOT/opencode-wrapper" "$PKG_DIR/usr/bin/opencode-v2"

install -m 0755 "$ROOT/opencode-backend" "$PKG_DIR/usr/share/opencode-v2-plugin/opencode-backend"
install -m 0755 "$ROOT/opencode-wrapper" "$PKG_DIR/usr/share/opencode-v2-plugin/opencode-wrapper"
install -m 0755 "$ROOT/functions" "$PKG_DIR/usr/share/opencode-v2-plugin/functions"
install -m 0644 "$ROOT/settings.json" "$PKG_DIR/usr/share/opencode-v2-plugin/settings.json"

cp -a "$PAGE_DIST/." "$PKG_DIR/var/www/mos-plugins/opencode-v2/"
if [ -f "$ROOT/images/opencode.png" ]; then
  install -m 0644 "$ROOT/images/opencode.png" "$PKG_DIR/var/www/mos-plugins/opencode-v2/icon.png"
fi

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: opencode-v2-plugin
Version: ${VERSION}-1+mos-plugin
Architecture: all
Maintainer: hustyanzu
Section: utils
Priority: optional
Description: OpenCode v2 plugin for MOS
 OpenCode v2 with a MOS-managed runtime and optional server.
EOF

cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
PLG=/boot/optional/plugins/opencode-v2
SHARE=/usr/share/opencode-v2-plugin
mkdir -p "$PLG/bin" "$PLG/config" "$PLG/data" "$PLG/state"
chmod 0755 /usr/bin/plugins/opencode-v2 /usr/bin/opencode /usr/bin/opencode-v2 2>/dev/null || true
for f in opencode-backend opencode-wrapper functions; do
  cp -f "$SHARE/$f" "$PLG/$f"
done
chmod 0755 "$PLG/opencode-backend" "$PLG/opencode-wrapper" "$PLG/functions" 2>/dev/null || true
if [ ! -f "$PLG/settings.json" ]; then
  cp -f "$SHARE/settings.json" "$PLG/settings.json"
fi
if [ -x "$PLG/bin/opencode" ]; then
  install -m 0755 "$PLG/bin/opencode" /usr/bin/opencode-v2.real 2>/dev/null || true
  if [ "$(jq -r '.server_enabled // false' "$PLG/settings.json" 2>/dev/null)" = "true" ] && \
     [ "$(jq -r '.auto_start // true' "$PLG/settings.json" 2>/dev/null)" = "true" ]; then
    /usr/bin/plugins/opencode-v2 start >/dev/null 2>&1 || true
  fi
fi
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postinst"

cat > "$PKG_DIR/DEBIAN/prerm" <<'EOF'
#!/bin/bash
if [ -x /usr/bin/plugins/opencode-v2 ]; then
  /usr/bin/plugins/opencode-v2 stop >/dev/null 2>&1 || true
fi
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/prerm"

cat > "$PKG_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/bash
rm -f /usr/bin/opencode-v2.real
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postrm"

echo "==> building ${DEB_FILE}"
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
else
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  printf '2.0\n' > "$WORK/debian-binary"
  ( cd "$PKG_DIR/DEBIAN" && tar --owner=0 --group=0 --numeric-owner -czf "$WORK/control.tar.gz" . )
  ( cd "$PKG_DIR" && tar --owner=0 --group=0 --numeric-owner --exclude=./DEBIAN -czf "$WORK/data.tar.gz" . )
  ( cd "$WORK" && ar rcs "$DEB_FILE" debian-binary control.tar.gz data.tar.gz )
fi

md5sum "$DEB_FILE" | awk '{print $1}' > "$DEB_FILE.md5"

echo
echo "Package: $DEB_FILE"
echo "MD5:     $(cat "$DEB_FILE.md5")"
echo
echo "Install on MOS:  dpkg -i $(basename "$DEB_FILE")"
echo "Then open Plugins -> OpenCode v2 and click Install."