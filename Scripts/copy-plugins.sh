#!/bin/sh -e

#  copy-plugins.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.


shopt -s nullglob

# Copy device plugins
function copy_plugins {
    echo "Looking for plugins in $1"
    for f in "$1"/*Plugin.xcframework; do
      plugin=$(basename "$f")
      echo Copying plugin: $plugin to frameworks directory in app
      plugin_path="$(readlink "$f" || echo "$f")"
      platform_arch="${SWIFT_PLATFORM_TARGET_PREFIX}-${ARCHS_STANDARD// /_}${LLVM_TARGET_TRIPLE_SUFFIX}"
      plugin_destination_path="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/${plugin%.*}.framework"
      plugin_arch_platform_path="$plugin_path/${platform_arch}/${plugin%.*}.framework"
      rsync -va --exclude=Frameworks "${plugin_arch_platform_path}/." "${plugin_destination_path}"
      if [ "$EXPANDED_CODE_SIGN_IDENTITY" != "-" ] && [ "$EXPANDED_CODE_SIGN_IDENTITY" != "" ]; then
        export CODESIGN_ALLOCATE=${DT_TOOLCHAIN_DIR}/usr/bin/codesign_allocate
        echo "Signing ${plugin} with ${EXPANDED_CODE_SIGN_IDENTITY_NAME}"
        /usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} --timestamp=none --preserve-metadata=identifier,entitlements,flags "$plugin_destination_path"
      else
        echo "Skipping signing, no identity set"
      fi
      
      dependencies=$(plutil -extract PluginDependencies xml1 -o - "${plugin_arch_platform_path}/Info.plist" | sed -n "s/.*<string>\(.*\)<\/string>.*/\1/p")
      echo "Dependencies = ${dependencies}"
      
      for framework in ${dependencies}; do
        framework_path="$1/${framework}.xcframework/${platform_arch}/${framework}.framework"
        echo "Copying plugin's framework $framework_path to ${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/."
        cp -avf "$framework_path" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/."
        plugin_path="$(readlink "$f" || echo "$f")"
        if [ "$EXPANDED_CODE_SIGN_IDENTITY" != "-" ] && [ "$EXPANDED_CODE_SIGN_IDENTITY" != "" ]; then
          echo "Signing $framework for $plugin with $EXPANDED_CODE_SIGN_IDENTITY_NAME"
          /usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} --timestamp=none --preserve-metadata=identifier,entitlements,flags "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/${framework}.framework"
        fi
      done
    done
}

copy_plugins "$BUILT_PRODUCTS_DIR"

copy_plugins "${SRCROOT}/Carthage/Build"
