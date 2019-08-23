#!/bin/sh -eu

#  build-derived-assets.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.


echo "Building DerivedAssets.xcassets"

output="${BUILT_PRODUCTS_DIR}/DerivedAssets.xcassets"
cp -a "${PROJECT_DIR}/Loop/DefaultAssets.xcassets/." "$output"

override="${PROJECT_DIR}/../AssetOverrides.xcassets/."

if [ -d $override ]; then
   echo "Adding asset overrides to DerivedAssets.xcassets"
   cp -a "$override" "$output"
fi

