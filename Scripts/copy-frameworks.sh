#!/bin/sh -e

#  copy-frameworks.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.

date

CARTHAGE_BUILD_DIR="${SRCROOT}/Carthage/Build"
if [ -n "${IPHONEOS_DEPLOYMENT_TARGET}" ]; then
    CARTHAGE_BUILD_DIR="${CARTHAGE_BUILD_DIR}/iOS"
elif [ -n "${WATCHOS_DEPLOYMENT_TARGET}" ]; then
    CARTHAGE_BUILD_DIR="${CARTHAGE_BUILD_DIR}/watchOS"
else
    echo "ERROR: Unexpected deployment target type"
    exit 1
fi

for COUNTER in $(seq 0 $(($SCRIPT_INPUT_FILE_COUNT - 1))); do
    SCRIPT_INPUT_VAR="SCRIPT_INPUT_FILE_${COUNTER}"
    echo "Stripping binary file from framework path for ${!SCRIPT_INPUT_VAR}"
    export ${SCRIPT_INPUT_VAR}="$(dirname "${!SCRIPT_INPUT_VAR}")"

    CARTHAGE_BUILD_FILE="${!SCRIPT_INPUT_VAR/${BUILT_PRODUCTS_DIR}/${CARTHAGE_BUILD_DIR}}"
    if [ -e "${CARTHAGE_BUILD_FILE}" ]; then
        echo "Substituting \"${CARTHAGE_BUILD_FILE}\" for \"${!SCRIPT_INPUT_VAR}\""
        export ${SCRIPT_INPUT_VAR}="${CARTHAGE_BUILD_FILE}"
    elif [ -e "${!SCRIPT_INPUT_VAR}" ]; then
        echo "Using original path: \"${!SCRIPT_INPUT_VAR}\""
    else
        echo "ERROR: Input file not found at \"${!SCRIPT_INPUT_FILE}\""
        exit 1
    fi
    # Resolve any symlinks
    export ${SCRIPT_INPUT_VAR}="$(readlink "${!SCRIPT_INPUT_VAR}" || echo "${!SCRIPT_INPUT_VAR}")"
    echo "copy-frameworks resolved path: ${!SCRIPT_INPUT_VAR}"
done

echo "Copy Frameworks with Carthage"
if [ -n "${GITHUB_ACCESS_TOKEN}" ]; then
    GITHUB_ACCESS_TOKEN=$GITHUB_ACCESS_TOKEN carthage copy-frameworks
else
    carthage copy-frameworks
fi
