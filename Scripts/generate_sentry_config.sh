#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <output-plist>" >&2
    exit 1
fi

OUT_PATH="$1"
OUT_DIR="$(dirname "${OUT_PATH}")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/patcher/SpliceKit/Configuration/Version.xcconfig"

read_version() {
    awk -F= '/SPLICEKIT_VERSION/ { gsub(/[ ;]/, "", $2); print $2; exit }' "${VERSION_FILE}"
}

ENVIRONMENT="${SPLICEKIT_SENTRY_ENVIRONMENT:-production}"
ENABLE_LOGS="${SPLICEKIT_SENTRY_ENABLE_LOGS:-${SPLICEKIT_SENTRY_LOGS_ENABLED:-true}}"
RELEASE_NAME="splicekit@$(read_version)"

enable_logs_plist_tag() {
    case "$(echo "${ENABLE_LOGS}" | tr '[:upper:]' '[:lower:]')" in
        0|false|no|off) echo "false/" ;;
        *) echo "true/" ;;
    esac
}

mkdir -p "${OUT_DIR}"

cat > "${OUT_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Environment</key>
    <string>${ENVIRONMENT}</string>
    <key>EnableLogs</key>
    <$(enable_logs_plist_tag)>
    <key>ReleaseName</key>
    <string>${RELEASE_NAME}</string>
</dict>
</plist>
EOF

echo "Generated ${OUT_PATH}"
