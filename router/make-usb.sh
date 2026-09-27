#!/usr/bin/env bash
# Prepare a USB stick for Entware on a Keenetic KN-1012 (ARM64), on macOS.
#   router/make-usb.sh            # lists external disks
#   router/make-usb.sh disk4      # ERASES disk4: one ext4 partition "OPKG" with install/EN_aarch64-installer.tar.gz inside
# Needs: brew install e2fsprogs. Asks for your password once (sudo) to write the filesystem.
set -euo pipefail
INSTALLER_URL="https://bin.entware.net/aarch64-k3.10/installer/EN_aarch64-installer.tar.gz"
MKFS="$(brew --prefix e2fsprogs)/sbin/mkfs.ext4"
DEBUGFS="$(brew --prefix e2fsprogs)/sbin/debugfs"
[ -x "$MKFS" ] || { echo "run: HOMEBREW_NO_AUTO_UPDATE=1 brew install e2fsprogs" >&2; exit 1; }

d="${1:-}"
if [ -z "$d" ]; then diskutil list external physical; echo "then: $0 diskN"; exit 0; fi
d="${d#/dev/}"
info=$(diskutil info "/dev/$d") || { echo "no such disk: $d" >&2; exit 1; }
# Refuse anything that is not a whole external USB disk.
echo "$info" | grep -qE 'Device Location: +External' || { echo "$d is not external, refusing" >&2; exit 1; }
echo "$info" | grep -qE 'Protocol: +USB'               || { echo "$d is not USB, refusing" >&2; exit 1; }
echo "$info" | grep -qE 'Part of Whole: +'"$d"'$'      || { echo "$d is a partition; pass the whole disk (e.g. disk4)" >&2; exit 1; }
echo "$info" | grep -E 'Device / Media Name|Disk Size'
read -r -p "ALL DATA on /dev/$d will be erased. Type YES to continue: " ok
[ "$ok" = YES ] || { echo "aborted"; exit 1; }

stage=$(mktemp -d); trap 'sudo rm -rf "$stage"' EXIT
mkdir -p "$stage/install"
curl -fL --retry 3 -o "$stage/install/EN_aarch64-installer.tar.gz" "$INSTALLER_URL"
tar -tzf "$stage/install/EN_aarch64-installer.tar.gz" >/dev/null   # archive is intact

diskutil eraseDisk FAT32 OPKG MBR "/dev/$d"     # creates the partition table and ${d}s1
diskutil unmountDisk "/dev/$d"
# The staged files must belong to root: mkfs -d copies owners, and the drive's top folder becomes the router's /opt.
# Owned by this Mac's user (uid 501), dropbear on the router refuses every SSH key (seen 2026-09-28).
chmod 755 "$stage" "$stage/install"; sudo chown -R 0:0 "$stage"
# ext4 with the installer already inside (-d); features newer kernels add are switched off for the router's kernel
sudo "$MKFS" -F -L OPKG -O ^metadata_csum,^metadata_csum_seed,^orphan_file -d "$stage" "/dev/${d}s1"
sudo "$DEBUGFS" -R "ls -l /install" "/dev/${d}s1" 2>/dev/null | grep -q EN_aarch64-installer || { echo "installer missing on the stick" >&2; exit 1; }
diskutil eject "/dev/$d"
echo "done: plug the stick into the router's USB port"
