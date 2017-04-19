#!/bin/bash


export PROJ_FILE="./Loop.xcodeproj/project.pbxproj"

echo -n "Enter a new handle.  A single word, usually lower-case, no special characters: "
read NEW_HANDLE

sed -i '' "s/MAIN_APP_BUNDLE_IDENTIFIER = com\..*\.Loop/MAIN_APP_BUNDLE_IDENTIFIER = com.${NEW_HANDLE}.Loop/g" "${PROJ_FILE}"

open Loop.xcodeproj
