#!/bin/sh -e

#  copy-plugins.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.


shopt -s nullglob

# Copy device plugins
function copy_plugins {
    echo "Looking for plugins in $1"
    for f in "$1"/*.loopplugin; do
      plugin=$(basename "$f")
      echo Copying device plugin: $plugin to frameworks directory in app
      plugin_path="$(readlink "$f" || echo "$f")"
      plugin_as_framework_path="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/${plugin%.*}.framework"
      rsync -va --exclude=Frameworks "$plugin_path/." "${plugin_as_framework_path}"
      # Rename .plugin to .framework
      if [ "$EXPANDED_CODE_SIGN_IDENTITY" != "-" ] && [ "$EXPANDED_CODE_SIGN_IDENTITY" != "" ]; then
        export CODESIGN_ALLOCATE=${DT_TOOLCHAIN_DIR}/usr/bin/codesign_allocate
        echo "Signing ${plugin} with ${EXPANDED_CODE_SIGN_IDENTITY_NAME}"
        /usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} --timestamp=none --preserve-metadata=identifier,entitlements,flags "$plugin_as_framework_path"
      else
        echo "Skipping signing, no identity set"
      fi
      for framework_path in "${f}"/Frameworks/*.framework; do
        framework=$(basename "$framework_path")
        echo "Copying plugin's framework $framework_path to ${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/."
        cp -a "$framework_path" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/."
        plugin_path="$(readlink "$f" || echo "$f")"
        if [ "$EXPANDED_CODE_SIGN_IDENTITY" != "-" ] && [ "$EXPANDED_CODE_SIGN_IDENTITY" != "" ]; then
          echo "Signing $framework for $plugin with $EXPANDED_CODE_SIGN_IDENTITY_NAME"
          /usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} --timestamp=none --preserve-metadata=identifier,entitlements,flags "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/${framework}"
        fi
      done
    done
}

copy_plugins "$BUILT_PRODUCTS_DIR"

CARTHAGE_BUILD_DIR="${SRCROOT}/Carthage/Build"
if [ -n "${IPHONEOS_DEPLOYMENT_TARGET}" ]; then
CARTHAGE_BUILD_DIR="${CARTHAGE_BUILD_DIR}/iOS"
elif [ -n "${WATCHOS_DEPLOYMENT_TARGET}" ]; then
CARTHAGE_BUILD_DIR="${CARTHAGE_BUILD_DIR}/watchOS"
else
echo "ERROR: Unexpected deployment target type"
exit 1
fi

copy_plugins "$CARTHAGE_BUILD_DIR"
