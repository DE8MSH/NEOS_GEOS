#!/usr/bin/env bash
set -euo pipefail

# Fast incremental builder for R46H GEOS/ARM M15.14 / 1.6.14.
# Reuses the proven M14.4 Buildroot toolchain/hardware cache, but forces and
# verifies the M15.14 rootfs payload so stale initramfs metadata cannot survive.

DOWNLOADS="${DOWNLOADS:-$HOME/Downloads}"
ARCHIVE="${ARCHIVE:-$DOWNLOADS/r46h-geos-arm-m15.14.tar.gz}"
CACHE_ROOT="${CACHE_ROOT:-$DOWNLOADS/r46h-geos-arm-m14.4}"
SRC="$DOWNLOADS/r46h-geos-arm"
CACHE_BR="$CACHE_ROOT/buildroot"
CACHE_HW="$CACHE_ROOT/hardware"

fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Host-Tool fehlt: $1"; }

for cmd in tar strings sed grep gzip cpio sha256sum cmp; do need "$cmd"; done

echo "=== R46H GEOS/ARM M15.14 fast build ==="
echo "Archive : $ARCHIVE"
echo "Cache   : $CACHE_ROOT"

[ -f "$ARCHIVE" ] || fail "Archiv fehlt: $ARCHIVE"
[ -d "$CACHE_BR/output/host" ] || fail "Buildroot-Cache fehlt: $CACHE_BR/output/host"
[ -x "$CACHE_BR/output/host/bin/aarch64-buildroot-linux-musl-gcc" ] || \
    fail "fertige AArch64-Toolchain fehlt im Cache"
[ -d "$CACHE_HW" ] || fail "Hardware-Ordner fehlt: $CACHE_HW"

rm -rf "$SRC"
tar xzf "$ARCHIVE" -C "$DOWNLOADS"
[ -d "$SRC" ] || fail "Archiv hat nicht r46h-geos-arm/ erzeugt"
cd "$SRC"

[ "$(cat VERSION 2>/dev/null || true)" = "1.6.14" ] || fail "VERSION ist nicht 1.6.14"
[ "$(sed -n 's/^GEOS_ARM_VERSION = //p' br2-external/package/geos-arm/geos-arm.mk | head -1)" = "1.6.14" ] || fail "geos-arm.mk ist nicht 1.6.14"
OVERLAY_RELEASE="br2-external/board/r46h/rootfs-overlay/etc/geos-release"
OVERLAY_INIT="br2-external/board/r46h/rootfs-overlay/init"
grep -qx 'GEOS_RELEASE=M15.14' "$OVERLAY_RELEASE" || fail "Overlay Release ist nicht M15.14"
grep -qx 'GEOS_VERSION=1.6.14' "$OVERLAY_RELEASE" || fail "Overlay Version ist nicht 1.6.14"
grep -qx 'GEOS_BUILD_ID=r46h-geos-arm-m15.14' "$OVERLAY_RELEASE" || fail "Overlay Build-ID ist nicht M15.14"
grep -q 'expected M15.14' "$OVERLAY_INIT" || fail "Overlay /init erwartet nicht M15.14"
grep -q 'GEOS_BUILD_ID=r46h-geos-arm-m15.14' scripts/make-image.sh || fail "make-image.sh Build-ID ist nicht M15.14"

# Link only the known-good expensive cache trees.
rm -rf buildroot hardware
ln -s "$CACHE_BR" buildroot
ln -s "$CACHE_HW" hardware

echo
echo "=== Cache links ==="
printf 'Buildroot -> %s\n' "$(readlink -f buildroot)"
printf 'Hardware  -> %s\n' "$(readlink -f hardware)"

# Guard the proven WEXT supplicant from an accidental package rebuild.
TARGET_WPA="$SRC/buildroot/output/target/usr/sbin/wpa_supplicant"
[ -x "$TARGET_WPA" ] || fail "wpa_supplicant fehlt im alten Target"
WPA_STRINGS="$SRC/buildroot/output/.r46h-wpa-fast.strings"
strings "$TARGET_WPA" > "$WPA_STRINGS"
grep -qx 'wext' "$WPA_STRINGS" || fail "vorhandener wpa_supplicant enthält kein WEXT"
WPA_BUILD_DIR="$(find "$SRC/buildroot/output/build" -maxdepth 1 -type d -name 'wpa_supplicant-*' -print -quit 2>/dev/null || true)"
if [ -n "$WPA_BUILD_DIR" ]; then
    touch "$WPA_BUILD_DIR/.stamp_built" "$WPA_BUILD_DIR/.stamp_staging_installed" "$WPA_BUILD_DIR/.stamp_target_installed"
fi

make -C buildroot BR2_EXTERNAL="$SRC/br2-external" r46h_geos_defconfig

echo
echo "=== geos-arm M15.14 / 1.6.14 neu bauen ==="
make -C buildroot BR2_EXTERNAL="$SRC/br2-external" geos-arm-dirclean
make -C buildroot BR2_EXTERNAL="$SRC/br2-external" geos-arm

TARGET="$SRC/buildroot/output/target"
TARGET_GEOS="$TARGET/usr/bin/geos-arm"
TARGET_RELEASE="$TARGET/etc/geos-release"
TARGET_INIT="$TARGET/init"
[ -x "$TARGET_GEOS" ] || fail "geos-arm wurde nicht ins Target installiert"

# Belt-and-suspenders: force the release-critical overlay files into the cached
# target even if an old Buildroot package stamp/overlay-finalize state survived.
install -D -m 0755 "$OVERLAY_INIT" "$TARGET_INIT"
install -D -m 0644 "$OVERLAY_RELEASE" "$TARGET_RELEASE"
install -D -m 0755 br2-external/board/r46h/rootfs-overlay/usr/libexec/r46h-wifi-autostart "$TARGET/usr/libexec/r46h-wifi-autostart"

GEOS_STRINGS="$SRC/buildroot/output/.r46h-geos-m1514.strings"
strings "$TARGET_GEOS" > "$GEOS_STRINGS"
grep -q 'M15.14 userspace start' "$GEOS_STRINGS" || fail "M15.14 Marker fehlt im Target-Binary"
grep -q 'GEOS/ARM TCP MODEM M15.14' "$GEOS_STRINGS" || fail "M15.14 TCP-Modem Marker fehlt im Target-Binary"
grep -qx 'GEOS_RELEASE=M15.14' "$TARGET_RELEASE" || fail "Target RootFS Release ist nicht M15.14"
grep -qx 'GEOS_VERSION=1.6.14' "$TARGET_RELEASE" || fail "Target RootFS Version ist nicht 1.6.14"
grep -qx 'GEOS_BUILD_ID=r46h-geos-arm-m15.14' "$TARGET_RELEASE" || fail "Target RootFS Build-ID ist nicht M15.14"
! grep -q 'M15\.7\|M15\.6' "$TARGET_INIT" || fail "Target /init enthält noch eine alte Release-ID"

echo "TARGET: M15.14 / 1.6.14 konsistent"

strings "$TARGET_WPA" > "$WPA_STRINGS"
grep -qx 'wext' "$WPA_STRINGS" || fail "WEXT ist vor RootFS-Erzeugung verschwunden"

# Force filesystem regeneration. rootfs-cpio-rebuild is preferred; fallback is
# for older Buildroot trees that do not expose that convenience target.
echo
echo "=== initramfs wirklich neu erzeugen ==="
if ! make -C buildroot BR2_EXTERNAL="$SRC/br2-external" rootfs-cpio-rebuild; then
    echo "rootfs-cpio-rebuild nicht verfügbar; verwende erzwungenen Fallback"
    rm -f buildroot/output/images/rootfs.cpio buildroot/output/images/rootfs.cpio.gz
    make -C buildroot BR2_EXTERNAL="$SRC/br2-external" -j"$(nproc)"
fi

ROOTFS="$SRC/buildroot/output/images/rootfs.cpio.gz"
[ -s "$ROOTFS" ] || fail "rootfs.cpio.gz fehlt"
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT

gzip -dc "$ROOTFS" | (cd "$VERIFY_DIR" && cpio -id --quiet 'etc/geos-release' 'init' 'usr/bin/geos-arm')
[ -r "$VERIFY_DIR/etc/geos-release" ] || fail "initramfs enthält kein /etc/geos-release"
[ -x "$VERIFY_DIR/init" ] || fail "initramfs enthält kein ausführbares /init"
[ -x "$VERIFY_DIR/usr/bin/geos-arm" ] || fail "initramfs enthält kein geos-arm"
grep -qx 'GEOS_RELEASE=M15.14' "$VERIFY_DIR/etc/geos-release" || fail "INITRAMFS selbst enthält nicht M15.14"
grep -qx 'GEOS_VERSION=1.6.14' "$VERIFY_DIR/etc/geos-release" || fail "INITRAMFS selbst enthält nicht 1.6.14"
grep -q 'expected M15.14' "$VERIFY_DIR/init" || fail "INITRAMFS /init erwartet nicht M15.14"

# With `set -o pipefail`, `strings binary | grep -q marker` is unsafe: grep -q
# exits as soon as it sees the marker and GNU strings can then die with SIGPIPE
# (141), making the successful marker check look like a failure.  Compare the
# payload byte-for-byte first, then inspect a materialized strings file.
if ! cmp -s "$TARGET_GEOS" "$VERIFY_DIR/usr/bin/geos-arm"; then
    echo "Target geos-arm:" >&2
    sha256sum "$TARGET_GEOS" >&2
    echo "Initramfs geos-arm:" >&2
    sha256sum "$VERIFY_DIR/usr/bin/geos-arm" >&2
    fail "INITRAMFS geos-arm unterscheidet sich vom frisch gebauten Target-Binary"
fi

INITRAMFS_GEOS_STRINGS="$VERIFY_DIR/geos-arm.strings"
strings "$VERIFY_DIR/usr/bin/geos-arm" > "$INITRAMFS_GEOS_STRINGS"
grep -q 'M15.14 userspace start' "$INITRAMFS_GEOS_STRINGS" || {
    echo "Gefundene Release-Marker im initramfs-Binary:" >&2
    grep -E 'M15\.[0-9]+ userspace start|GEOS/ARM TCP MODEM M15\.[0-9]+' "$INITRAMFS_GEOS_STRINGS" >&2 || true
    fail "INITRAMFS geos-arm ist nicht M15.14"
}
grep -q 'GEOS/ARM TCP MODEM M15.14' "$INITRAMFS_GEOS_STRINGS" || fail "INITRAMFS enthält das TCP-Modem nicht"

echo "INITRAMFS geos-arm SHA256: $(sha256sum "$VERIFY_DIR/usr/bin/geos-arm" | awk '{print $1}')"
echo "INITRAMFS: M15.14 / 1.6.14 verifiziert"

strings "$TARGET_WPA" > "$WPA_STRINGS"
grep -qx 'wext' "$WPA_STRINGS" || fail "WEXT nach RootFS-Build verloren"

for f in idbloader.img uboot.img trust.img Image rk3326-r46h-linux.dtb; do
    [ -f "$SRC/hardware/$f" ] || fail "Hardware-Datei fehlt: hardware/$f"
done

echo
echo "=== SD-Image bauen ==="
./scripts/make-image.sh

IMAGE="$SRC/output/r46h-geos-arm.img"
RELEASE_FILE="$SRC/output/GEOS-RELEASE.TXT"
[ -s "$IMAGE" ] || fail "Image wurde nicht erzeugt: $IMAGE"
[ -r "$RELEASE_FILE" ] || fail "GEOS-RELEASE.TXT fehlt"
grep -qx 'GEOS_RELEASE=M15.14' "$RELEASE_FILE" || fail "BOOT Release ist nicht M15.14"
grep -qx 'GEOS_VERSION=1.6.14' "$RELEASE_FILE" || fail "BOOT Version ist nicht 1.6.14"
grep -qx 'GEOS_BUILD_ID=r46h-geos-arm-m15.14' "$RELEASE_FILE" || fail "BOOT Build-ID ist nicht M15.14"

echo
echo "=============================================="
echo "FERTIG: M15.14 / 1.6.14"
ls -lh "$IMAGE" "$ROOTFS"
sha256sum "$IMAGE"
echo "Release metadata:"
cat "$RELEASE_FILE"
echo "=============================================="
