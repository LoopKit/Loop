#!/bin/sh

#  install-scenarios.sh
#  Loop
#
#  Created by Pete Schwamb on 12/19/22.
#  Copyright © 2022 LoopKit Authors. All rights reserved.

SCENARIOS_DIR="$WORKSPACE_ROOT"/Scenarios

if [ -d "$SCENARIOS_DIR" ]
then
    echo "$SCENARIOS_DIR exists. Installing scenarios."
    echo cp -a "$SCENARIOS_DIR" "${BUILT_PRODUCTS_DIR}/Scenarios"
    cp -a "$SCENARIOS_DIR" "${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Scenarios"
else
    echo "Scenarios missing or not configured... Not installing."
fi
