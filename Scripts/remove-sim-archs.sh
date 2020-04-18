
#!/bin/sh -e

APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"

# This script loops through the frameworks embedded in the application and
# removes x86_64 and i386 architectures.
find "$APP_PATH" -name '*.framework' -type d | while read -r FRAMEWORK
do
    FRAMEWORK_EXECUTABLE_NAME=$(defaults read "$FRAMEWORK/Info.plist" CFBundleExecutable)
    FRAMEWORK_EXECUTABLE_PATH="$FRAMEWORK/$FRAMEWORK_EXECUTABLE_NAME"

    if [ ! -f "${FRAMEWORK_EXECUTABLE_PATH}" ]; then
        continue
    fi

    echo "Thinning framework $FRAMEWORK_EXECUTABLE_NAME"

    if xcrun lipo -info "${FRAMEWORK_EXECUTABLE_PATH}" | grep --silent "Non-fat"; then
        echo "   Framework non-fat, skipping"
        continue
    fi

    ARCHS=$(lipo -archs "$FRAMEWORK_EXECUTABLE_PATH")

    for ARCH in $ARCHS
    do
       if [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "i386" ]; then
        echo "   Removing $ARCH from $FRAMEWORK_EXECUTABLE_NAME"
        xcrun lipo -remove "$ARCH" "$FRAMEWORK_EXECUTABLE_PATH" -o "$FRAMEWORK_EXECUTABLE_PATH"
       fi
    done
done

