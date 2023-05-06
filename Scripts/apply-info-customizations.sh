#!/bin/sh -e

#  apply-info-customizations.sh
#  Loop
#
#  Created by Pete Schwamb on 4/25/23.
#  Copyright © 2023 LoopKit Authors. All rights reserved.


SCRIPT="$(basename "${0}")"
SCRIPT_DIRECTORY="$(dirname "${0}")"

error() {
  echo "ERROR: ${*}" >&2
  echo "Usage: ${SCRIPT} [-i|--info-plist-path info-plist-path]" >&2
  echo "Parameters:" >&2
  echo "  -i|--info-plist-path <info-plist-path>                     path to the Info.plist file to modify; optional, defaults to \${BUILT_PRODUCTS_DIR}/\${INFOPLIST_PATH}" >&2
  exit 1
}

warn() {
  echo "WARN: ${*}" >&2
}

info() {
  echo "INFO: ${*}" >&2
}

info_plist_path="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
while [[ $# -gt 0 ]]
do
  case $1 in
    -i|--info-plist-path)
      info_plist_path="${2}"
      shift 2
      ;;
  esac
done

if [ ${#} -ne 0 ]; then
  error "Unexpected arguments: ${*}"
fi

if [ "${info_plist_path}" == "/" -o ! -e "${info_plist_path}" ]; then
  error "Must provide valid --info-plist-path, or have valid \${BUILT_PRODUCTS_DIR} and \${INFOPLIST_PATH} set."
fi

info "Applying info.plist customizations from ../InfoCustomizations.txt"

while read -r -a words; do                # iterate over lines of input
  set -- "${words[@]}"                 # update positional parameters
  for word; do
    if [[ $word = *"="* ]]; then       # if a word contains an "="...
        key=${word%%=*}
        value=${word#*=}
        echo "Key = $key"
        echo "Value = $value"
        plutil -replace $key -string "${value}" "${info_plist_path}"
    fi
  done
done <"../InfoCustomizations.txt"
