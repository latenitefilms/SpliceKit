#!/bin/bash
# Install a SwiftPM executable and its resource bundles side by side.
set -eu

binary="$1"
shift
for destination in "$@"; do
    mkdir -p "$destination"
    cp "$binary" "$destination/"
    for bundle in "$(dirname "$binary")"/*.bundle; do
        [ -d "$bundle" ] || continue
        rsync -a "$bundle" "$destination/"
    done
done
