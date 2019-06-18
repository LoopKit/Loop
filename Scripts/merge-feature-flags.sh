#!/bin/sh
  
#  merge-feature-flags.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.

echo "Merging feature flags"

MERGED_FILE=${SCRIPT_OUTPUT_FILE_0}

if [ -e "${MERGED_FILE}" ]; then
    echo "Removing old merged file"
    rm ${MERGED_FILE}
fi

for COUNTER in $(seq 0 $(($SCRIPT_INPUT_FILE_COUNT - 1))); do
    SCRIPT_INPUT_FILE="SCRIPT_INPUT_FILE_${COUNTER}"
    FEATURE_PLIST=${!SCRIPT_INPUT_FILE}
    if [ -e "${FEATURE_PLIST}" ]; then
        echo "Adding features from \"${FEATURE_PLIST}\" to \"${MERGED_FILE}\""
        echo /usr/libexec/PlistBuddy -c \"Merge ${FEATURE_PLIST}\" \"${MERGED_FILE}\"
        /usr/libexec/PlistBuddy -c "Merge ${FEATURE_PLIST}" "${MERGED_FILE}"
    else
        echo "Skipping missing input file \"${FEATURE_PLIST}\""
    fi
done

echo "Merged feature flags in ${MERGED_FILE}"
