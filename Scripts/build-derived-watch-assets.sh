#!/bin/sh -eu

#  build-derived-watch-assets.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.

echo "Building DerivedAssets.xcassets for Watch App"

watch_output="${PROJECT_DIR}/WatchApp/DerivedAssets.xcassets"

watch_override="${PROJECT_DIR}/../AdditionalWatchAssets.xcassets/."

if [ -d $watch_override ]; then
   echo "Adding asset overrides to WatchApp/DerivedAssets.xcassets"
   cp -a "$watch_override" "$watch_output"
fi
