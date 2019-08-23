#!/bin/sh -eu

#  build-derived-watch-assets.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.

echo "Building WatchDerivedAssets.xcassets"

watch_output="${BUILT_PRODUCTS_DIR}/DerivedWatchAssets.xcassets"
cp -a "${PROJECT_DIR}/WatchApp/DefaultAssets.xcassets/." "$watch_output"


watch_override="${PROJECT_DIR}/../WatchAssetOverrides.xcassets/."

if [ -d $watch_override ]; then
   echo "Adding asset overrides to DerivedWatchAssets.xcassets"
   cp -a "$watch_override" "$watch_output"
fi
