#!/bin/sh -e

#  capture-build-details.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.

echo "Gathering build details in ${SRCROOT}"
cd "${SRCROOT}"

plist="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

if [ -e .git ]; then
  rev=$(git rev-parse HEAD)
  plutil -replace com-loopkit-Loop-git-revision -string ${rev} "${plist}"
  branch=$(git branch | grep \* | cut -d ' ' -f2-)
  plutil -replace com-loopkit-Loop-git-branch -string "${branch}" "${plist}"
fi;
plutil -replace com-loopkit-Loop-srcroot -string "${SRCROOT}" "${plist}"
plutil -replace com-loopkit-Loop-build-date -string "$(date)" "${plist}"
plutil -replace com-loopkit-Loop-xcode-version -string "${XCODE_PRODUCT_BUILD_VERSION}" "${plist}"

