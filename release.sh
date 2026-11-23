#!/bin/bash
set -e

# SpliceKit Release Script — fully automated
# Usage: ./release.sh <version> "<release notes>"
# Example: ./release.sh 3.0.0 "New feature X, fix Y"

VERSION="$1"
NOTES="$2"
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version> [\"release notes\"]"
    echo "Example: ./release.sh 3.0.0 \"Wizard UI, DMG distribution\""
    exit 1
fi
if [ -z "$NOTES" ]; then
    NOTES="Bug fixes and improvements"
fi

SIGN_ID="${SIGN_ID:-Developer ID Application: LateNite Films Pty Ltd (A5HDJTY9X5)}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-SpliceKit}"
XCODE_PROJECT="Patcher/SpliceKit.xcodeproj"
VERSION_FILE="Patcher/SpliceKit/Configuration/Version.xcconfig"
BUILD_DIR="Patcher/build"
BUILT_APP="${BUILD_DIR}/Build/Products/Release/SpliceKit.app"
PATCHER_DSYM="${BUILD_DIR}/Build/Products/Release/SpliceKit.app.dSYM"
RUNTIME_DSYM="build/SpliceKit.dSYM"
DMG_NAME="SpliceKit-v${VERSION}.dmg"
DMG_PATH="Patcher/${DMG_NAME}"
SPARKLE_SIGN="/tmp/bin/sign_update"
SPARKLE_GENERATE_KEYS="/tmp/bin/generate_keys"
PATCHER_INFO_PLIST="Patcher/SpliceKit/Resources/Info.plist"
RELEASE_NOTES_URL="${RELEASE_NOTES_URL:-https://latenitefilms.github.io/SpliceKit/releasenotes.html}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-Documentation/releasenotes.html}"

CURRENT_BRANCH="$(git branch --show-current)"
PUSH_REMOTE="$(git config --get branch.${CURRENT_BRANCH}.remote || echo origin)"
PUSH_BRANCH="$(git config --get branch.${CURRENT_BRANCH}.merge | sed 's#refs/heads/##')"
if [ -z "${PUSH_BRANCH}" ]; then
    PUSH_BRANCH="${CURRENT_BRANCH}"
fi
REMOTE_URL="$(git remote get-url "${PUSH_REMOTE}")"
RELEASE_REPO="$(printf '%s' "${REMOTE_URL}" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
TAG_NAME="v${VERSION}"

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "ERROR: Working tree is dirty. Commit, stash, or remove local changes before releasing." >&2
    git status --short >&2
    exit 1
fi

echo "[0/15] Checking notarization profile..."
NOTARY_PREFLIGHT_LOG="$(mktemp)"
if ! xcrun notarytool history --keychain-profile "${KEYCHAIN_PROFILE}" >/dev/null 2>"${NOTARY_PREFLIGHT_LOG}"; then
    cat "${NOTARY_PREFLIGHT_LOG}" >&2
    rm -f "${NOTARY_PREFLIGHT_LOG}"
    echo "ERROR: Notarization profile ${KEYCHAIN_PROFILE} is not ready. Fix Apple Developer agreements or credentials before releasing." >&2
    exit 1
fi
rm -f "${NOTARY_PREFLIGHT_LOG}"

ensure_sparkle_tools() {
    if [ -x "${SPARKLE_SIGN}" ] && [ -x "${SPARKLE_GENERATE_KEYS}" ]; then
        return 0
    fi
    echo "  Downloading Sparkle tools..."
    SPARKLE_URL=$(curl -s https://api.github.com/repos/sparkle-project/Sparkle/releases/latest | python3 -c "import sys,json; [print(a['browser_download_url']) for a in json.loads(sys.stdin.read())['assets'] if a['name'].endswith('.tar.xz')]")
    curl -sL "${SPARKLE_URL}" -o /tmp/sparkle.tar.xz
    (cd /tmp && tar xf sparkle.tar.xz)
}

# The patcher only accepts updates signed by the key whose public half is
# SUPublicEDKey in its Info.plist. Refuse to release if that doesn't match the
# Sparkle key in this Mac's keychain, or every installed copy would reject it.
echo "[0/15] Checking Sparkle signing key..."
ensure_sparkle_tools
PLIST_ED_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "${PATCHER_INFO_PLIST}" 2>/dev/null || true)"
SIGNING_ED_KEY="$("${SPARKLE_GENERATE_KEYS}" -p 2>/dev/null | tail -1 | tr -d '[:space:]')"
if [ -z "${SIGNING_ED_KEY}" ] || [ "${PLIST_ED_KEY}" != "${SIGNING_ED_KEY}" ]; then
    echo "ERROR: SUPublicEDKey in ${PATCHER_INFO_PLIST} (${PLIST_ED_KEY:-missing}) does not match" >&2
    echo "       this Mac's Sparkle signing key (${SIGNING_ED_KEY:-not found; run ${SPARKLE_GENERATE_KEYS}})." >&2
    exit 1
fi

resolve_built_app() {
    local products_dir="${BUILD_DIR}/Build/Products/Release"
    local candidate=""

    while IFS= read -r app; do
        if [ -f "${app}/Contents/Info.plist" ] && [ -d "${app}/Contents/Frameworks/Sparkle.framework" ]; then
            candidate="${app}"
            break
        fi
    done < <(find "${products_dir}" -maxdepth 1 -type d -name "*.app" | sort)

    if [ -z "${candidate}" ]; then
        while IFS= read -r app; do
            if [ -f "${app}/Contents/Info.plist" ]; then
                candidate="${app}"
                break
            fi
        done < <(find "${products_dir}" -maxdepth 1 -type d -name "*.app" | sort)
    fi

    if [ -z "${candidate}" ]; then
        echo "ERROR: Could not locate built app bundle in ${products_dir}" >&2
        exit 1
    fi

    BUILT_APP="${candidate}"
}

update_version_file() {
    python3 - "$VERSION_FILE" "$VERSION" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text()
updated, count = re.subn(r"^SPLICEKIT_VERSION\s*=\s*.*$", f"SPLICEKIT_VERSION = {version}", text, flags=re.M)
if count != 1:
    raise SystemExit(f"ERROR: failed to update SPLICEKIT_VERSION in {path}")
path.write_text(updated)
PY
}

update_release_notes_html() {
    python3 - "${RELEASE_NOTES_FILE}" "${VERSION}" "${NOTES}" <<'PY'
from datetime import datetime
from html import escape
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
notes = sys.argv[3].strip() or "Bug fixes and improvements"

if not path.exists():
    raise SystemExit(f"ERROR: release notes HTML not found: {path}")

text = path.read_text(encoding="utf-8")
if re.search(rf"<h1>SpliceKit {re.escape(version)}</h1>", text):
    print(f"  Release notes already contain v{version}; skipping")
    raise SystemExit(0)

def ordinal(day):
    if 10 <= day % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(day % 10, "th")
    return f"{day}{suffix}"

today = datetime.now()
released = f"{ordinal(today.day)} {today.strftime('%B %Y')}"
note_items = [
    re.sub(r"^[-*]\s+", "", line.strip())
    for line in re.split(r"\r?\n+", notes)
    if line.strip()
]
items_html = "\n".join(f"\t\t\t\t<li>{escape(item)}</li>" for item in note_items)
section = f"""\t\t\t<h1>SpliceKit {escape(version)}</h1>

\t\t\t<h2>🎉 Released</h2>

\t\t\t<ul>
\t\t\t\t<li>{escape(released)}</li>
\t\t\t</ul>

\t\t\t<h2>🔨 Improvements</h2>

\t\t\t<ul>
{items_html}
\t\t\t</ul>

\t\t\t<hr />
"""

marker = '<div class="content">'
idx = text.find(marker)
if idx == -1:
    raise SystemExit(f"ERROR: could not find release notes content container in {path}")
insert_pos = idx + len(marker)
updated = text[:insert_pos] + "\n" + section + text[insert_pos:].lstrip("\n")
path.write_text(updated, encoding="utf-8")
print(f"  Release notes HTML updated: {path}")
PY
}

echo "=== SpliceKit Release v${VERSION} ==="
echo ""

# ──────────────────────────────────────────────
# BUILD
# ──────────────────────────────────────────────

echo "[1/15] Bumping version to ${VERSION}..."
update_version_file

echo "[2/15] Building SpliceKit dylib + tools..."
make clean
make
make tools
make symbols

echo "[3/15] Building transcription helpers..."
for tool in parakeet-transcriber whisper-transcriber; do
    swift build -c release --arch arm64 --arch x86_64 --package-path "Tools/$tool"
done

echo "[4/15] Building SpliceKit app via Xcode..."
xcodebuild -project "${XCODE_PROJECT}" \
    -scheme SpliceKit \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    ONLY_ACTIVE_ARCH=NO \
    clean build

resolve_built_app
PATCHER_DSYM="$(find "${BUILD_DIR}/Build/Products/Release" -maxdepth 1 -name "*.app.dSYM" | head -n 1)"
echo "  Using app bundle: ${BUILT_APP}"

echo "[4b/15] Building insert_dylib helper..."
INSERT_DYLIB_BUILD_DIR="${BUILD_DIR}/insert_dylib-src"
INSERT_DYLIB_BIN="${BUILD_DIR}/insert_dylib"
rm -rf "${INSERT_DYLIB_BUILD_DIR}"
mkdir -p "${INSERT_DYLIB_BUILD_DIR}"
curl -fLsS https://github.com/tyilo/insert_dylib/archive/refs/heads/master.zip \
    -o "${INSERT_DYLIB_BUILD_DIR}/insert_dylib.zip"
unzip -qo "${INSERT_DYLIB_BUILD_DIR}/insert_dylib.zip" -d "${INSERT_DYLIB_BUILD_DIR}"
clang -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -o "${INSERT_DYLIB_BIN}" \
    "${INSERT_DYLIB_BUILD_DIR}/insert_dylib-master/insert_dylib/main.c" \
    -framework Foundation
rm -rf "${INSERT_DYLIB_BUILD_DIR}"
if [ ! -x "${INSERT_DYLIB_BIN}" ]; then
    echo "ERROR: insert_dylib helper was not built at ${INSERT_DYLIB_BIN}" >&2
    exit 1
fi
echo "  Built: $(lipo -info "${INSERT_DYLIB_BIN}")"

echo "[5/15] Adding the release helper to the app..."
APP_RES="${BUILT_APP}/Contents/Resources"
for tool in parakeet-transcriber whisper-transcriber; do
    lipo "${APP_RES}/tools/$tool" -verify_arch arm64
    lipo "${APP_RES}/tools/$tool" -verify_arch x86_64
done
cp "${INSERT_DYLIB_BIN}" "${APP_RES}/tools/insert_dylib"
chmod +x "${APP_RES}/tools/insert_dylib"
echo "  Bundled insert_dylib helper"

# ──────────────────────────────────────────────
# SIGN
# ──────────────────────────────────────────────

echo "[7/15] Signing embedded binaries (inner-to-outer)..."
SPARKLE_FW="${BUILT_APP}/Contents/Frameworks/Sparkle.framework"

# Sign Sparkle XPC services first (innermost)
for xpc in "${SPARKLE_FW}/Versions/B/XPCServices/"*.xpc; do
    if [ -d "$xpc" ]; then
        codesign --force --options runtime --timestamp --sign "${SIGN_ID}" "$xpc"
        echo "  Signed: $(basename "$xpc")"
    fi
done

# Sign Sparkle Updater.app
if [ -d "${SPARKLE_FW}/Versions/B/Updater.app" ]; then
    codesign --force --options runtime --timestamp --sign "${SIGN_ID}" "${SPARKLE_FW}/Versions/B/Updater.app"
    echo "  Signed: Updater.app"
fi

# Sign Sparkle Autoupdate helper
if [ -f "${SPARKLE_FW}/Versions/B/Autoupdate" ]; then
    codesign --force --options runtime --timestamp --sign "${SIGN_ID}" "${SPARKLE_FW}/Versions/B/Autoupdate"
    echo "  Signed: Autoupdate"
fi

# Sign Sparkle framework
codesign --force --options runtime --timestamp --sign "${SIGN_ID}" "${SPARKLE_FW}"
echo "  Signed: Sparkle.framework"

# Sign all Mach-O binaries in Resources (dylib, tools)
find "${BUILT_APP}/Contents/Resources" -type f | while read f; do
    if file -b "$f" 2>/dev/null | grep -q "Mach-O"; then
        codesign --force --options runtime --timestamp --sign "${SIGN_ID}" "$f"
        echo "  Signed: $(basename "$f")"
    fi
done

echo "[8/15] Signing app bundle..."
codesign --force --options runtime --timestamp --sign "${SIGN_ID}" "${BUILT_APP}"
codesign --verify --deep --strict "${BUILT_APP}"
echo "  Verification passed"

# ──────────────────────────────────────────────
# CREATE DMG
# ──────────────────────────────────────────────

echo "[9/15] Creating DMG..."
DMG_TEMP="${BUILD_DIR}/dmg_staging"
rm -rf "${DMG_TEMP}" "${DMG_PATH}"
mkdir -p "${DMG_TEMP}"
cp -R "${BUILT_APP}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

hdiutil create -volname "SpliceKit" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_PATH}"
rm -rf "${DMG_TEMP}"
echo "  DMG: ${DMG_PATH} ($(du -h "${DMG_PATH}" | cut -f1))"

# ──────────────────────────────────────────────
# NOTARIZE
# ──────────────────────────────────────────────

echo "[10/15] Submitting DMG for notarization (this may take a few minutes)..."
xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${KEYCHAIN_PROFILE}" --wait

echo "[11/15] Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"
echo "  Stapled: ${DMG_PATH}"

# ──────────────────────────────────────────────
# SPARKLE APPCAST
# ──────────────────────────────────────────────

echo "[12/15] Generating Sparkle EdDSA signature..."
ensure_sparkle_tools
SPARKLE_SIG=$("${SPARKLE_SIGN}" "${DMG_PATH}" | grep -o 'edSignature="[^"]*"' | sed 's/edSignature="//;s/"//')
FILE_SIZE=$(stat -f%z "${DMG_PATH}")
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
echo "  Signature: ${SPARKLE_SIG}"

echo "[13/15] Updating appcast.xml..."
# Build the new item XML
NEW_ITEM="    <item>
      <title>SpliceKit v${VERSION}</title>
      <sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url=\"https://github.com/${RELEASE_REPO}/releases/download/v${VERSION}/${DMG_NAME}\"
        sparkle:edSignature=\"${SPARKLE_SIG}\"
        length=\"${FILE_SIZE}\"
        type=\"application/octet-stream\" />
    </item>"

# Insert after <language>en</language>
python3 -c "
import sys
with open('appcast.xml', 'r') as f:
    content = f.read()
marker = '<language>en</language>'
idx = content.find(marker)
if idx == -1:
    print('ERROR: Could not find marker in appcast.xml', file=sys.stderr)
    sys.exit(1)
insert_pos = idx + len(marker)
new_content = content[:insert_pos] + '\n' + '''${NEW_ITEM}''' + content[insert_pos:]
with open('appcast.xml', 'w') as f:
    f.write(new_content)
print('  Appcast updated')
"

echo "  Updating ${RELEASE_NOTES_FILE}..."
update_release_notes_html

# ──────────────────────────────────────────────
# GIT + GITHUB RELEASE
# ──────────────────────────────────────────────

echo "[14/15] Committing and pushing..."
git add appcast.xml "${VERSION_FILE}" "${RELEASE_NOTES_FILE}"
git commit -m "Release v${VERSION}: ${NOTES}"
git push "${PUSH_REMOTE}" "HEAD:${PUSH_BRANCH}"

if git rev-parse -q --verify "refs/tags/${TAG_NAME}" >/dev/null; then
    git tag -d "${TAG_NAME}"
fi
git tag -a "${TAG_NAME}" -m "Release ${TAG_NAME}"

LOCAL_TAG_SHA="$(git rev-parse "${TAG_NAME}^{}")"
REMOTE_TAG_SHA="$(git ls-remote --tags "${PUSH_REMOTE}" "refs/tags/${TAG_NAME}^{}" | awk '{print $1}')"
if [ -n "${REMOTE_TAG_SHA}" ] && [ "${REMOTE_TAG_SHA}" != "${LOCAL_TAG_SHA}" ]; then
    echo "ERROR: Remote tag ${TAG_NAME} already exists on ${PUSH_REMOTE} at ${REMOTE_TAG_SHA}, expected ${LOCAL_TAG_SHA}" >&2
    exit 1
fi
if [ -z "${REMOTE_TAG_SHA}" ]; then
    git push "${PUSH_REMOTE}" "refs/tags/${TAG_NAME}:refs/tags/${TAG_NAME}"
fi

echo "[15/15] Creating GitHub release..."
if gh release create "${TAG_NAME}" "${DMG_PATH}" \
    -R "${RELEASE_REPO}" \
    --verify-tag \
    --title "${TAG_NAME}" \
    --notes "${NOTES}"; then
    RELEASE_URL=$(gh release view "${TAG_NAME}" -R "${RELEASE_REPO}" --json url -q '.url')
else
    echo "ERROR: Failed to create GitHub release ${TAG_NAME}" >&2
    exit 1
fi

echo ""
echo "========================================="
echo "  Release v${VERSION} complete!"
echo "  ${RELEASE_URL}"
echo "========================================="
echo ""
echo "  - Built via Xcode, signed, notarized, stapled"
echo "  - DMG: ${DMG_PATH}"
echo "  - Appcast updated with EdDSA signature"
echo "  - Release notes HTML updated"
echo "  - Pushed to main, GitHub release created"
echo "  - Sparkle will auto-notify users"
echo ""
