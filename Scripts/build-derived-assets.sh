#!/bin/sh -eu

#
#  build-derived-assets.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.
#

SCRIPT="$(basename "${0}")"

error() {
  echo "ERROR: ${*}" >&2
  echo "Usage: ${SCRIPT} <directory>" >&2
  echo "Parameters:" >&2
  echo "  <directory>  directory with derived assets" >&2
  exit 1
}

info() {
  echo "INFO: ${*}" >&2
}

if [ ${#} -lt 1 ]; then
  error "Missing arguments"
fi

DIRECTORY="${1}"
shift 1

if [ ${#} -ne 0 ]; then
  error "Unexpected arguments: ${*}"
fi

if [ ! -d "${DIRECTORY}" ]; then 
    error "Directory '${DIRECTORY}' does not exist"
fi

DERIVED_ASSETS="${DIRECTORY}/DerivedAssets.xcassets"
DERIVED_ASSETS_BASE="${DIRECTORY}/DerivedAssetsBase.xcassets"

# Assets can be overridden by a DerivedAssetsOverride.xcassets in ${DIRECTORY}, or
# By a file named ${DIRECTORY}/../../OverrideAssets${EXECUTABLE_NAME}.xcassets

DERIVED_ASSETS_OVERRIDE="${DIRECTORY}/DerivedAssetsOverride.xcassets"
if [ ! -e "${DERIVED_ASSETS_OVERRIDE}" ]; then
  DERIVED_ASSETS_OVERRIDE="${DIRECTORY}/../../OverrideAssets${EXECUTABLE_NAME}.xcassets"
fi

info "Building derived assets for ${DIRECTORY}..."
rm -rf "${DERIVED_ASSETS}"

info "Copying derived assets base to derived assets..."
cp -av "${DERIVED_ASSETS_BASE}" "${DERIVED_ASSETS}"

if [ -e "${DERIVED_ASSETS_OVERRIDE}" ]; then
  info "Copying derived assets override to derived assets..."
  for ASSET_PATH in "${DERIVED_ASSETS_OVERRIDE}"/*; do
    ASSET_FILE="$(basename "${ASSET_PATH}")"
    rm -rf "${DERIVED_ASSETS}/${ASSET_FILE}"
    cp -av "${ASSET_PATH}" "${DERIVED_ASSETS}/${ASSET_FILE}"
  done
fi
