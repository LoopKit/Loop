#!/bin/sh

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
    SCRIPT_INPUT_FILE="SCRIPT_INPUT_FILE_${COUNTER}"
    CARTHAGE_BUILD_FILE="${!SCRIPT_INPUT_FILE/${BUILT_PRODUCTS_DIR}/${CARTHAGE_BUILD_DIR}}"
    if [ -e "${CARTHAGE_BUILD_FILE}" ]; then
        if [ -e "${SCRIPT_INPUT_FILE}" ]; then
            echo "ERROR: Duplicate frameworks found at:"
            echo "  ${SCRIPT_INPUT_FILE}"
            echo "  ${CARTHAGE_BUILD_FILE}"
            exit 1
        fi
        echo "Substituting \"${CARTHAGE_BUILD_FILE}\" for \"${!SCRIPT_INPUT_FILE}\""
        export ${SCRIPT_INPUT_FILE}="${CARTHAGE_BUILD_FILE}"
    elif [ -e "${!SCRIPT_INPUT_FILE}" ]; then
        echo "Using original path: \"${!SCRIPT_INPUT_FILE}\""
    else
        echo "ERROR: Input file not found at \"${!SCRIPT_INPUT_FILE}\""
        exit 1
    fi
done

echo "Copy Frameworks with Carthage"
carthage copy-frameworks
