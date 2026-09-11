#!/usr/bin/env sh
set -eu

printf '%s\n' 'Optical block devices:'
lsblk -o NAME,PATH,TYPE,VENDOR,MODEL,TRAN | awk 'NR == 1 || $3 == "rom"'
printf '\n%s\n' 'Matching Linux SCSI generic devices (often required by MakeMKV):'
for block in /sys/class/block/sr*; do
  [ -e "$block/device" ] || continue
  block_device=$(readlink -f "$block/device")
  for generic in /sys/class/scsi_generic/sg*; do
    [ -e "$generic/device" ] || continue
    if [ "$(readlink -f "$generic/device")" = "$block_device" ]; then
      printf '/dev/%s (matches /dev/%s)\n' "${generic##*/}" "${block##*/}"
    fi
  done
done
