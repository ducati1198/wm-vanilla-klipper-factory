#!/bin/bash
# ./snapshot.sh create | verify | usb | status
# The factory snapshot: the factory stack of the board, saved once, checked, copied to a USB stick.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/common.sh"; . "$HERE/lib/snapshot.sh"
case "${1:-status}" in
    create) print_active && fail "a print is running."; snapshot_create ;;
    verify) snapshot_verify && ok "snapshot is complete and matches its checksums" || fail "snapshot is damaged or missing" ;;
    usb)    snapshot_verify || fail "the board's snapshot is damaged. Not copying."; snapshot_usb_copy ;;
    status) if snapshot_exists; then cat "$SNAP_DIR/MANIFEST"; snapshot_verify && ok "checksums match" || warn "checksums do NOT match"; else say "no snapshot yet"; fi ;;
    *) sed -n 2,3p "$0"; exit 1 ;;
esac
