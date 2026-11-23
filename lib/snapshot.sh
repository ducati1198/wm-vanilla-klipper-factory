#!/bin/bash
# Factory snapshot: save the factory stack once, check it, copy it to a USB stick.
# Sourced by snapshot.sh, install.sh and restore.sh (needs lib/common.sh first).

snapshot_exists() { [ -f "$SNAP_DIR/SHA256SUMS" ] && [ -f "$SNAP_DIR/home.tar.gz" ]; }

snapshot_create() {   # never overwrites an existing snapshot
    snapshot_exists && { say "      factory snapshot already exists: $SNAP_DIR (kept, not overwritten)"; return 0; }
    mkdir -p "$SNAP_DIR" || fail "cannot create $SNAP_DIR"
    local items=() i
    for i in $SNAP_HOME_ITEMS; do [ -e "$HOME_DIR/$i" ] && items+=("$i"); done
    [ "${#items[@]}" -gt 0 ] || fail "none of the factory folders exist in $HOME_DIR. Nothing to save."
    # shellcheck disable=SC2086
    tar -C "$HOME_DIR" $SNAP_HOME_EXCLUDES -czf "$SNAP_DIR/home.tar.gz" "${items[@]}" || fail "could not write home.tar.gz"
    local sys=()
    for i in $SNAP_SYS_ITEMS; do [ -e "$SYS_ROOT/$i" ] && sys+=("$i"); done
    if [ "${#sys[@]}" -gt 0 ]; then
        $SUDO tar -C "$SYS_ROOT" -czf "$SNAP_DIR/system.tar.gz" "${sys[@]}" || fail "could not write system.tar.gz"
        $SUDO chown "$(id -un)" "$SNAP_DIR/system.tar.gz" 2>/dev/null || true
    fi
    : >"$SNAP_DIR/services.state"
    for i in $STACK_SERVICES makerbase-client makerbase-webcam; do
        [ -n "$(service_enabled "$i")" ] && echo "$i $(service_enabled "$i") $(service_active "$i")" >>"$SNAP_DIR/services.state"
    done
    { echo "date: $(date -Is)"; echo "board: $(board_model)"; echo "home: ${items[*]}"; echo "system: ${sys[*]:-none}"
      echo "tm_t1_factory_settings: $([ -d "$HOME_DIR/TM_T1/factory_settings" ] && echo yes || echo no)"; } >"$SNAP_DIR/MANIFEST"
    ( cd "$SNAP_DIR" && sha256sum home.tar.gz $([ -f system.tar.gz ] && echo system.tar.gz) services.state MANIFEST >SHA256SUMS )
    chmod 444 "$SNAP_DIR"/* 2>/dev/null
    ok "factory snapshot saved: $SNAP_DIR ($(du -sm "$SNAP_DIR" | cut -f1) MB)"
}

snapshot_verify() {   # $1 = folder (default: the local one)
    local d="${1:-$SNAP_DIR}"
    [ -f "$d/SHA256SUMS" ] || { say "no SHA256SUMS in $d"; return 1; }
    ( cd "$d" && sha256sum -c --quiet SHA256SUMS >/dev/null 2>&1 )
}

usb_find() {   # a mounted removable drive (WM_USB_DIR overrides)
    [ -n "${WM_USB_DIR:-}" ] && [ -d "$WM_USB_DIR" ] && { echo "$WM_USB_DIR"; return 0; }
    local m
    for m in /media/*/* /media/* /mnt/*; do
        [ -d "$m" ] && [ -w "$m" ] && mountpoint -q "$m" 2>/dev/null && { echo "$m"; return 0; }
    done
    return 1
}

snapshot_usb_copy() {   # copy the snapshot to a stick and check the copy; the local copy stays
    snapshot_exists || fail "no snapshot to copy. Run ./snapshot.sh create first."
    local u dest; u="$(usb_find)" || fail "no USB stick found. Plug it into the board, wait 10 seconds, try again (or give the folder: WM_USB_DIR=/path)."
    dest="$u/wm-factory-snapshot"
    mkdir -p "$dest" && cp -a "$SNAP_DIR/." "$dest/" || fail "copy to $u failed (stick full or read-only?)"
    cp -a "$HERE/restore.sh" "$HERE/lib" "$dest/" 2>/dev/null
    printf 'Factory snapshot of the WonderMaker screen board.\nRestore: copy this folder back to ~/wm-factory-snapshot or run: ./restore.sh --factory --from %s\n' "$dest" >"$dest/README.txt"
    sync
    snapshot_verify "$dest" || fail "the copy on the stick does not match (bad stick?). The board's own copy is fine."
    ok "copied to the USB stick and checked: $dest (the copy on the board stays)"
}
