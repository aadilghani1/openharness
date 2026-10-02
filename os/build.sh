#!/usr/bin/env bash
# Build on x86_64 Arch Linux as root (the workflow uses an isolated container).
set -euo pipefail
OS_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
[[ $(uname -m) == x86_64 && $EUID == 0 ]] || { echo 'Build requires x86_64 Linux and root.' >&2; exit 1; }
cd "$OS_DIR"
VERSION=$(python3 -c 'import json; print(json.load(open("lock.json"))["version"])')
SNAPSHOT=$(python3 -c 'import json; print(json.load(open("lock.json"))["arch_snapshot"])')
BUILD_DIR=${HARNESS_OS_BUILD_DIR:-$OS_DIR/work}
mkdir -p "$BUILD_DIR" "$OS_DIR/dist"
[[ ! -e "$BUILD_DIR/profile" ]] || { echo 'Use a fresh build directory; refusing to reuse an incomplete image.' >&2; exit 1; }
cp -a /usr/share/archiso/configs/releng "$BUILD_DIR/profile"
PROFILE="$BUILD_DIR/profile"
# The source profile supplies the upstream BIOS/UEFI boot machinery only.
rm -rf "$PROFILE/airootfs"
mkdir -p "$PROFILE/airootfs"
cp packages.x86_64 "$PROFILE/packages.x86_64"
cat > "$PROFILE/pacman.conf" <<EOF
[options]
Architecture = auto
CheckSpace
ParallelDownloads = 8
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
[harness-build]
SigLevel = Optional TrustAll
Server = file://$BUILD_DIR/repo
[core]
Server = https://archive.archlinux.org/repos/$SNAPSHOT/\$repo/os/\$arch
[extra]
Server = https://archive.archlinux.org/repos/$SNAPSHOT/\$repo/os/\$arch
EOF
mkdir -p "$BUILD_DIR/package/usr/lib/harness" "$BUILD_DIR/repo"
cp -a root/. "$BUILD_DIR/package/"
cp installer.py "$BUILD_DIR/package/usr/lib/harness-os/install.py"
install -m 755 tools/customize-live.sh "$BUILD_DIR/package/usr/lib/harness-os/setup-live"
install -m 755 tools/hn-os "$BUILD_DIR/package/usr/bin/hn-os"
cp lock.json "$BUILD_DIR/package/usr/share/harness-os/lock.json"
if [[ -n ${HARNESS_OS_RUNTIME_DIR:-} ]]; then
    install -m 755 "$HARNESS_OS_RUNTIME_DIR/harness-tui" "$BUILD_DIR/package/usr/lib/harness/harness-tui"
    install -m 644 "$HARNESS_OS_RUNTIME_DIR/cli.js" "$BUILD_DIR/package/usr/lib/harness/cli.mjs"
    install -m 644 "$HARNESS_OS_RUNTIME_DIR/notify.mjs" "$BUILD_DIR/package/usr/lib/harness/notify.mjs"
else
    python3 tools/fetch.py "$BUILD_DIR/package/usr/lib/harness"
    mv "$BUILD_DIR/package/usr/lib/harness/hn" "$BUILD_DIR/package/usr/lib/harness/harness-tui"
fi
ln -s harness-tui "$BUILD_DIR/package/usr/lib/harness/hn"
python3 - "$BUILD_DIR/package/usr/lib/harness" "$BUILD_DIR/package/usr/share/harness-os/runtime.json" <<'PY'
import hashlib, json, os, sys
from pathlib import Path
root = Path(sys.argv[1])
data = {'source_commit': os.environ.get('HARNESS_OS_SOURCE_SHA'),
        'mode': 'source' if os.environ.get('HARNESS_OS_RUNTIME_DIR') else 'published',
        'files': {p.name: {'sha256': hashlib.file_digest(p.open('rb'), 'sha256').hexdigest(), 'bytes': p.stat().st_size}
                  for p in root.iterdir() if p.is_file() and not p.is_symlink()}}
Path(sys.argv[2]).write_text(json.dumps(data, indent=2) + '\n')
PY
find "$BUILD_DIR/package/usr/bin" "$BUILD_DIR/package/usr/lib/harness-os" -type f -exec chmod 755 {} +
chmod 755 "$BUILD_DIR/package/usr/share/harness-os/labwc/"{autostart,shutdown}
cat > "$BUILD_DIR/package/.PKGINFO" <<EOF
pkgname = harness-os
pkgbase = harness-os
pkgver = 0.1.0-1
pkgdesc = Programmer OS session and verified Harness runtime
url = https://github.com/autonomous-ai/openharness
builddate = ${SOURCE_DATE_EPOCH:-$(date +%s)}
packager = OpenHarness
size = $(du -sb "$BUILD_DIR/package" | cut -f1)
arch = x86_64
license = MIT
depend = nodejs-lts-jod
depend = tmux
depend = foot
depend = labwc
EOF
cat > "$BUILD_DIR/package/.INSTALL" <<'EOF'
post_install() {
    /usr/lib/harness-os/setup-live
}
EOF
bsdtar --zstd -cf "$BUILD_DIR/repo/harness-os-0.1.0-1-x86_64.pkg.tar.zst" -C "$BUILD_DIR/package" .PKGINFO .INSTALL etc usr
repo-add "$BUILD_DIR/repo/harness-build.db.tar.gz" "$BUILD_DIR/repo/"*.pkg.tar.zst
cp -a live/. "$PROFILE/airootfs/"
cat >> "$PROFILE/profiledef.sh" <<EOF

iso_name="programmer-os"
iso_label="HN_OS"
iso_publisher="OpenHarness"
iso_application="Programmer OS: boot into hn"
iso_version="$VERSION"
airootfs_image_type="squashfs"
airootfs_image_tool_options=("-comp" "zstd" "-Xcompression-level" "6" "-b" "1M")
file_permissions=(
  ["/root"]="0:0:750"
)
EOF
# Use the same LTS kernel in the live USB and on disk.
python3 - "$PROFILE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
for d in ['syslinux', 'efiboot', 'grub']:
    for f in (p / d).rglob('*'):
        if f.is_file():
            try: s = f.read_text()
            except UnicodeDecodeError: continue
            s = s.replace('vmlinuz-linux', 'vmlinuz-linux-lts').replace('initramfs-linux.img', 'initramfs-linux-lts.img')
            s = s.replace('Arch Linux install medium', 'Programmer OS - try or install')
            f.write_text(s)
PY
mkarchiso -v -w "$BUILD_DIR/archiso" -o "$OS_DIR/dist" "$PROFILE"
python3 tools/manifest.py "$OS_DIR/dist" "$BUILD_DIR/archiso/x86_64/airootfs"
