#!/bin/sh -eu

#  build-derived-assets.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.


echo "Building DerivedAssets.xcassets"

output="${PROJECT_DIR}/Loop/DerivedAssets.xcassets"

override="${PROJECT_DIR}/../AdditionalAssets.xcassets/."

if [ -d $override ]; then
   echo "Adding asset overrides to DerivedAssets.xcassets"
   cp -a "$override" "$output"
fi

