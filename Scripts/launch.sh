#!/bin/bash
#
# Launch modded FCP with FCPBridge dylib injected
#

MODDED_APP="$HOME/Desktop/FinalCutPro_Modded/Final Cut Pro.app"
DYLIB="$MODDED_APP/Contents/Frameworks/FCPBridge.framework/Versions/A/FCPBridge"

if [ ! -f "$DYLIB" ]; then
    echo "ERROR: FCPBridge dylib not found at: $DYLIB"
    echo "Run 'make deploy' first."
    exit 1
fi

echo "=== Launching Final Cut Pro with FCPBridge ==="
echo "  Socket: /tmp/fcpbridge.sock"
echo "  PID will appear in Console.app under [FCPBridge]"
echo ""

export DYLD_INSERT_LIBRARIES="$DYLIB"
exec "$MODDED_APP/Contents/MacOS/Final Cut Pro"
