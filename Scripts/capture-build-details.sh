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

if [ -n "${EXPANDED_PROVISIONING_PROFILE}" ]; then
  PROFILE_EXPIRE_DATE=$(security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/${EXPANDED_PROVISIONING_PROFILE}.mobileprovision | plutil -p - | grep ExpirationDate | cut -b 23-)
  # Convert to plutil format
  PROFILE_EXPIRE_DATE=$(date -j -f "%Y-%m-%d %H:%M:%S" "${PROFILE_EXPIRE_DATE}" +"%Y-%m-%dT%H:%M:%SZ")
  plutil -replace com-loopkit-Loop-profile-expiration -date "${PROFILE_EXPIRE_DATE}" "${plist}"
fi;
