#!/bin/sh -e

#  embed-luped-pebblekit.sh
#  Loop
#
#  Adds the bluetooth-peripheral background mode that the Luped PPoGATT
#  service needs, only when the optional Luped transport is enabled
#  (LUPED_PEBBLE in SWIFT_ACTIVE_COMPILATION_CONDITIONS). Other builds are
#  left unchanged.

info_plist="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
plistbuddy=/usr/libexec/PlistBuddy

# Remove the PebbleKit framework embedded by earlier versions of this script.
rm -rf "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/PebbleKit.framework"

has_peripheral_mode() {
  "${plistbuddy}" -c "Print :UIBackgroundModes" "${info_plist}" 2>/dev/null | grep -qx '[[:space:]]*bluetooth-peripheral'
}

case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS} " in
  *" LUPED_PEBBLE "*)
    if ! has_peripheral_mode; then
      "${plistbuddy}" -c "Add :UIBackgroundModes: string bluetooth-peripheral" "${info_plist}"
    fi
    ;;
  *)
    # Undo a previous enabled build in the same build folder.
    if has_peripheral_mode; then
      index=$("${plistbuddy}" -c "Print :UIBackgroundModes" "${info_plist}" | sed '1d;$d' | grep -nx '[[:space:]]*bluetooth-peripheral' | cut -d : -f 1)
      "${plistbuddy}" -c "Delete :UIBackgroundModes:$((index - 1))" "${info_plist}"
    fi
    ;;
esac
