#!/bin/bash
# Bundle SpliceKit resources into the app during Xcode build phase
set -e

REPO_DIR="${PROJECT_DIR}/.."
APP_RESOURCES="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
PREBUILT="${BUILT_PRODUCTS_DIR}/SpliceKit_prebuilt"

mkdir -p "$APP_RESOURCES/mcp" "$APP_RESOURCES/tools" "$APP_RESOURCES/Scripts/lua"
cp "$PREBUILT/SpliceKit" "$APP_RESOURCES/SpliceKit"
cp "$REPO_DIR/MCP/server.py" "$REPO_DIR/MCP/requirements.txt" "$APP_RESOURCES/mcp/"
cp "$REPO_DIR/Documentation/Licenses/Lua.txt" "$APP_RESOURCES/Lua-LICENSE.txt"

# Sentry was removed; drop any config left from an earlier incremental build.
rm -f "$APP_RESOURCES/SpliceKitSentryConfig.plist"

# Copy Lua scripts
rsync -a --delete --exclude '.*' "$REPO_DIR/Lua Scripts/" "$APP_RESOURCES/Scripts/lua/"

# Copy tools
for tool in silence-detector structure-analyzer beat-detector SpliceKitMixer; do
    cp "$PREBUILT/$tool" "$APP_RESOURCES/tools/$tool"
done
if [ -f "$PREBUILT/insert_dylib" ]; then
    cp "$PREBUILT/insert_dylib" "$APP_RESOURCES/tools/insert_dylib"
    chmod +x "$APP_RESOURCES/tools/insert_dylib"
    echo "Bundled insert_dylib"
elif [ -f "$REPO_DIR/build/insert_dylib" ]; then
    cp "$REPO_DIR/build/insert_dylib" "$APP_RESOURCES/tools/insert_dylib"
    chmod +x "$APP_RESOURCES/tools/insert_dylib"
    echo "Bundled insert_dylib"
fi

# Developer builds can contain a transcriber package when its binary is unavailable.
for tool in parakeet-transcriber whisper-transcriber; do
    package="$REPO_DIR/Tools/$tool"
    destination="$APP_RESOURCES/tools/$tool"
    for configuration in release apple/Products/Release debug; do
        binary="$package/.build/$configuration/$tool"
        if [ -f "$binary" ]; then
            if [ -d "$destination" ]; then rm -rf "$destination"; fi
            bash "$PROJECT_DIR/scripts/copy_transcriber.sh" "$binary" "$APP_RESOURCES/tools"
            continue 2
        fi
    done
    if [ -f "$destination" ]; then rm -f "$destination"; fi
    mkdir -p "$destination"
    rsync -a --delete --exclude '.*' "$package/" "$destination/"
done

# SpliceKit no longer ships BRAW plugin bundles (BRAW Toolbox covers .braw);
# remove any copy left in the app from an earlier incremental build.
rm -rf "$APP_RESOURCES/BRAWPlugins"

echo "Resource bundling complete"
