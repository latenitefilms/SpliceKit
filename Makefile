CC = clang
ARCHS = -arch arm64 -arch x86_64
MACOSX_DEPLOYMENT_TARGET = 14.0
MIN_VERSION = -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
FRAMEWORKS = -framework Foundation -framework AppKit -framework AVFoundation -framework Speech -framework CoreServices -framework CoreImage -framework Metal -framework MetalKit -framework QuartzCore -framework Vision
MODULE_CACHE_DIR = $(BUILD_DIR)/ModuleCache
OBJC_FLAGS = -fobjc-arc -fmodules -fmodules-cache-path="$(abspath $(MODULE_CACHE_DIR))"
OBJCXX_FLAGS = $(OBJC_FLAGS) -std=c++17
DEBUG_FLAGS = -g
LINKER_FLAGS = -undefined dynamic_lookup -dynamiclib
CPP_LIBS = -lc++
INSTALL_NAME = -install_name @rpath/SpliceKit.framework/Versions/A/SpliceKit
VERSION_CONFIG = Patcher/SpliceKit/Configuration/Version.xcconfig
SPLICEKIT_VERSION = $(shell awk -F= '/SPLICEKIT_VERSION/ { gsub(/[ ;]/, "", $$2); print $$2; exit }' $(VERSION_CONFIG))
VERSION_DEFINE = -DSPLICEKIT_VERSION=\"$(SPLICEKIT_VERSION)\"
DSYM = $(OUTPUT).dSYM

OBJC_SOURCES = $(wildcard Sources/*.m)
OBJCXX_SOURCES = $(wildcard Sources/*.mm)
OBJS = $(patsubst Sources/%.m,$(BUILD_DIR)/obj/%.o,$(OBJC_SOURCES)) \
	$(patsubst Sources/%.mm,$(BUILD_DIR)/obj/%.o,$(OBJCXX_SOURCES))

BUILD_DIR = build
OUTPUT = $(BUILD_DIR)/SpliceKit

# Upstream Lua release and its published SHA-256 (https://www.lua.org/ftp/).
LUA_VERSION = 5.4.9
LUA_SHA256 = 2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6
LUA_URL ?= https://www.lua.org/ftp/lua-$(LUA_VERSION).tar.gz
LUA_DIR = $(BUILD_DIR)/lua-$(LUA_VERSION)/src
LUA_LIB = $(LUA_DIR)/liblua.a

# Modded app paths — auto-detect standard or Creator Studio edition
MODDED_APP_STANDARD = $(HOME)/Applications/SpliceKit/Final Cut Pro.app
MODDED_APP_CREATOR = $(HOME)/Applications/SpliceKit/Final Cut Pro Creator Studio.app
MODDED_APP = $(shell if [ -d "$(MODDED_APP_STANDARD)" ]; then echo "$(MODDED_APP_STANDARD)"; elif [ -d "$(MODDED_APP_CREATOR)" ]; then echo "$(MODDED_APP_CREATOR)"; else echo "$(MODDED_APP_STANDARD)"; fi)
FW_DIR = $(MODDED_APP)/Contents/Frameworks/SpliceKit.framework
ENTITLEMENTS = entitlements.plist
REGISTER_PRO_EXTENSION_APP = $(MODDED_APP)/Contents/Helpers/RegisterProExtension.app
PROAPP_SUPPORT_FRAMEWORK = $(MODDED_APP)/Contents/Frameworks/ProAppSupport.framework

SILENCE_DETECTOR = $(BUILD_DIR)/silence-detector
STRUCTURE_ANALYZER = $(BUILD_DIR)/structure-analyzer
BEAT_DETECTOR = $(BUILD_DIR)/beat-detector
MIXER_APP = $(BUILD_DIR)/SpliceKitMixer
SWIFT_TOOLS = $(SILENCE_DETECTOR) $(STRUCTURE_ANALYZER) $(BEAT_DETECTOR) $(MIXER_APP)
AUDIO_BUS_PROBE_DIR = Tools/audio-bus-probe-au
AUDIO_BUS_PROBE_COMPONENT = $(BUILD_DIR)/SpliceKitAudioBusProbe.component
AUDIO_BUS_PROBE_BINARY = $(AUDIO_BUS_PROBE_COMPONENT)/Contents/MacOS/SpliceKitAudioBusProbe
AUDIO_BUS_PROBE_INFO = $(AUDIO_BUS_PROBE_DIR)/Info.plist
AUDIO_BUS_PROBE_SOURCE = $(AUDIO_BUS_PROBE_DIR)/SpliceKitAudioBusProbe.c
AUDIO_BUS_PROBE_INSTALL_DIR = $(HOME)/Library/Audio/Plug-Ins/Components
TOOLS_DIR = $(HOME)/Applications/SpliceKit/tools

# --- VP9 codec bundle (Plugins/VP9 → FCP.app/Contents/PlugIns/Codecs) --------
VP9_SOURCE_DIR = Plugins/VP9/Sources
VP9_PRIVATE_DIR = $(VP9_SOURCE_DIR)/Private
VP9_BUILD_DIR = $(BUILD_DIR)/vp9
VP9_DECODER_BUNDLE = $(VP9_BUILD_DIR)/Codecs/SpliceKitVP9Decoder.bundle
VP9_DECODER_EXEC = $(VP9_DECODER_BUNDLE)/Contents/MacOS/SpliceKitVP9Decoder
VP9_DECODER_INFO = Plugins/VP9/Codecs/SpliceKitVP9Decoder.bundle/Contents/Info.plist
VP9_DECODER_SOURCES = $(VP9_SOURCE_DIR)/VP9VideoDecoder.mm
VP9_FRAMEWORKS = -framework Foundation -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox
VP9_CFLAGS = $(ARCHS) $(MIN_VERSION) $(OBJCXX_FLAGS) $(DEBUG_FLAGS) -fvisibility=hidden -I $(VP9_SOURCE_DIR) -I $(VP9_PRIVATE_DIR)
VP9_LDFLAGS = -bundle $(CPP_LIBS)

# --- MKV/WebM format reader (Plugins/MKV → FCP.app/Contents/PlugIns/FormatReaders) ---
MKV_SOURCE_DIR = Plugins/MKV/Sources
MKV_PRIVATE_DIR = $(MKV_SOURCE_DIR)/Private
MKV_LIBWEBM_DIR = $(MKV_SOURCE_DIR)/libwebm
MKV_BUILD_DIR = $(BUILD_DIR)/mkv
MKV_IMPORT_BUNDLE = $(MKV_BUILD_DIR)/FormatReaders/SpliceKitMKVImport.bundle
MKV_IMPORT_EXEC = $(MKV_IMPORT_BUNDLE)/Contents/MacOS/SpliceKitMKVImport
MKV_IMPORT_INFO = Plugins/MKV/FormatReaders/SpliceKitMKVImport.bundle/Contents/Info.plist
MKV_IMPORT_SOURCES = $(MKV_SOURCE_DIR)/MKVCommon.mm \
                      $(MKV_SOURCE_DIR)/MKVFormatReader.mm \
                      $(MKV_LIBWEBM_DIR)/mkvparser/mkvparser.cc \
                      $(MKV_LIBWEBM_DIR)/mkvparser/mkvreader.cc
MKV_FRAMEWORKS = -framework Foundation -framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework MediaToolbox -framework AudioToolbox
# libwebm uses its own exceptions/assert flow; keep default C++ settings but
# disable ObjC ARC for the .mm so we can freely mix with C++ heap types.
MKV_CFLAGS = $(ARCHS) $(MIN_VERSION) -fno-objc-arc -fmodules -fmodules-cache-path="$(abspath $(MODULE_CACHE_DIR))" -std=c++17 $(DEBUG_FLAGS) -fvisibility=hidden -Wno-deprecated-declarations -I $(MKV_SOURCE_DIR) -I $(MKV_PRIVATE_DIR) -I $(MKV_LIBWEBM_DIR)
MKV_LDFLAGS = -bundle $(CPP_LIBS)

.PHONY: all clean deploy launch tools url-import-tools audio-bus-probe install-audio-bus-probe uninstall-audio-bus-probe symbols vp9-prototype mkv-prototype mcp-setup mcp-doctor

all: $(OUTPUT)

symbols: $(DSYM)

tools: $(SWIFT_TOOLS)

audio-bus-probe: $(AUDIO_BUS_PROBE_BINARY)
	@echo "Built: $(AUDIO_BUS_PROBE_COMPONENT)"

$(AUDIO_BUS_PROBE_BINARY): $(AUDIO_BUS_PROBE_SOURCE) $(AUDIO_BUS_PROBE_INFO) | $(BUILD_DIR)
	@mkdir -p "$(AUDIO_BUS_PROBE_COMPONENT)/Contents/MacOS"
	@cp "$(AUDIO_BUS_PROBE_INFO)" "$(AUDIO_BUS_PROBE_COMPONENT)/Contents/Info.plist"
	$(CC) $(ARCHS) $(MIN_VERSION) -std=c11 -O2 -Wall -Wextra -Wno-deprecated-declarations \
		-fvisibility=hidden -dynamiclib \
		-framework AudioToolbox -framework AudioUnit -framework CoreAudio -framework CoreFoundation -framework CoreServices \
		"$(AUDIO_BUS_PROBE_SOURCE)" -o "$(AUDIO_BUS_PROBE_BINARY)"
	@codesign --force --sign - "$(AUDIO_BUS_PROBE_COMPONENT)" >/dev/null

install-audio-bus-probe: audio-bus-probe
	@mkdir -p "$(AUDIO_BUS_PROBE_INSTALL_DIR)"
	@rm -rf "$(AUDIO_BUS_PROBE_INSTALL_DIR)/SpliceKitAudioBusProbe.component"
	@cp -R "$(AUDIO_BUS_PROBE_COMPONENT)" "$(AUDIO_BUS_PROBE_INSTALL_DIR)/SpliceKitAudioBusProbe.component"
	@codesign --force --sign - "$(AUDIO_BUS_PROBE_INSTALL_DIR)/SpliceKitAudioBusProbe.component" >/dev/null
	@killall -9 AudioComponentRegistrar >/dev/null 2>&1 || true
	@echo "Installed: $(AUDIO_BUS_PROBE_INSTALL_DIR)/SpliceKitAudioBusProbe.component"

uninstall-audio-bus-probe:
	@rm -rf "$(AUDIO_BUS_PROBE_INSTALL_DIR)/SpliceKitAudioBusProbe.component"
	@killall -9 AudioComponentRegistrar >/dev/null 2>&1 || true
	@echo "Uninstalled: $(AUDIO_BUS_PROBE_INSTALL_DIR)/SpliceKitAudioBusProbe.component"

# ---------------------------------------------------------------------------
# MCP server setup (Python venv + dependencies)
# ---------------------------------------------------------------------------
MCP_VENV ?= $(HOME)/.venvs/splicekit-mcp
MCP_PYTHON = $(MCP_VENV)/bin/python
MCP_REQUIREMENTS = MCP/requirements.txt

mcp-setup:
	@PY="$$(command -v python3.13 || command -v python3.12 || command -v python3.11 || command -v python3)"; \
	if [ -z "$$PY" ]; then echo "[mcp-setup] python3 not found in PATH"; exit 1; fi; \
	echo "[mcp-setup] Using interpreter: $$PY ($$($$PY --version 2>&1))"; \
	if [ ! -x "$(MCP_PYTHON)" ]; then \
		echo "[mcp-setup] Creating venv at $(MCP_VENV)"; \
		"$$PY" -m venv "$(MCP_VENV)"; \
	else \
		echo "[mcp-setup] Reusing venv at $(MCP_VENV)"; \
	fi
	@"$(MCP_PYTHON)" -m pip install --upgrade --quiet pip
	@"$(MCP_PYTHON)" -m pip install --upgrade --quiet -r $(MCP_REQUIREMENTS)
	@echo "[mcp-setup] Installed:"; "$(MCP_PYTHON)" -m pip show mcp | awk '/^(Name|Version|Location):/'
	@echo "[mcp-setup] Set your MCP client command to $(MCP_PYTHON)"

mcp-doctor:
	@echo "== SpliceKit MCP doctor =="
	@if [ -x "$(MCP_PYTHON)" ]; then \
		echo "[ok] venv interpreter:    $(MCP_PYTHON) ($$($(MCP_PYTHON) --version 2>&1))"; \
	else \
		echo "[FAIL] venv interpreter missing at $(MCP_PYTHON) — run 'make mcp-setup'"; \
	fi
	@if [ -x "$(MCP_PYTHON)" ] && "$(MCP_PYTHON)" -c "import mcp.server.fastmcp" >/dev/null 2>&1; then \
		echo "[ok] mcp package:         $$($(MCP_PYTHON) -m pip show mcp | awk '/^Version:/{print $$2}')"; \
	else \
		echo "[FAIL] mcp package not importable in venv — run 'make mcp-setup'"; \
	fi
	@if [ -f .mcp.json ]; then \
		CMD=$$(/usr/bin/python3 -c "import json, os; print(os.path.expandvars(json.load(open('.mcp.json'))['mcpServers']['splicekit']['command']))" 2>/dev/null); \
		if [ "$$CMD" = "$(MCP_PYTHON)" ]; then \
			echo "[ok] .mcp.json command:   $$CMD"; \
		else \
			echo "[warn] .mcp.json command: $$CMD (expected $(MCP_PYTHON))"; \
		fi; \
	else \
		echo "[warn] .mcp.json not found in repo root"; \
	fi
	@if /usr/sbin/lsof -nP -iTCP:9876 -sTCP:LISTEN 2>/dev/null | grep -q LISTEN; then \
		echo "[ok] FCP bridge listening on 127.0.0.1:9876"; \
	else \
		echo "[warn] No process listening on :9876 — launch the modded Final Cut Pro"; \
	fi

url-import-tools:
	@mkdir -p "$(TOOLS_DIR)"
	@YTDLP_PATH="$$(command -v yt-dlp || true)"; \
	if [ -n "$$YTDLP_PATH" ]; then \
		ln -sf "$$YTDLP_PATH" "$(TOOLS_DIR)/yt-dlp"; \
		echo "Linked yt-dlp -> $$YTDLP_PATH"; \
	else \
		echo "yt-dlp not found in PATH. Install with: brew install yt-dlp"; \
	fi
	@FFMPEG_PATH="$$(command -v ffmpeg || true)"; \
	if [ -n "$$FFMPEG_PATH" ]; then \
		ln -sf "$$FFMPEG_PATH" "$(TOOLS_DIR)/ffmpeg"; \
		echo "Linked ffmpeg -> $$FFMPEG_PATH"; \
	else \
		echo "ffmpeg not found in PATH. Install with: brew install ffmpeg"; \
	fi
	@FFPROBE_PATH="$$(command -v ffprobe || true)"; \
	if [ -n "$$FFPROBE_PATH" ]; then \
		ln -sf "$$FFPROBE_PATH" "$(TOOLS_DIR)/ffprobe"; \
		echo "Linked ffprobe -> $$FFPROBE_PATH"; \
	else \
		echo "ffprobe not found in PATH. Install with: brew install ffmpeg"; \
	fi

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/obj: | $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/obj

$(SILENCE_DETECTOR): Tools/silence-detector.swift
$(STRUCTURE_ANALYZER): Tools/structure-analyzer.swift
$(BEAT_DETECTOR): Tools/beat-detector.swift
$(MIXER_APP): $(wildcard Tools/mixer-app/*.swift)
$(MIXER_APP): SWIFT_FLAGS = -parse-as-library

$(SWIFT_TOOLS): Makefile | $(BUILD_DIR)
	@set -eu; tmp=$$(mktemp -d "$@.XXXXXX"); trap 'rm -rf "$$tmp"' EXIT; \
		for arch in $(filter-out -arch,$(ARCHS)); do \
			swiftc -O -suppress-warnings $(SWIFT_FLAGS) -target "$$arch-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
				$(filter %.swift,$^) -o "$$tmp/$$arch"; \
		done; \
		lipo -create "$$tmp"/* -output "$@"
	@echo "Built: $@"

# Publish the source tree only after the entire archive has been verified.
$(LUA_DIR)/lua.h: | $(BUILD_DIR)
	@set -eu; tmp=$$(mktemp -d "$(BUILD_DIR)/lua-src.XXXXXX"); \
		trap 'rm -rf "$$tmp"' EXIT; \
		curl -fsSL --retry 3 "$(LUA_URL)" -o "$$tmp/lua.tar.gz"; \
		(cd "$$tmp" && printf '%s  lua.tar.gz\n' "$(LUA_SHA256)" | shasum -a 256 -c -); \
		tar -xzf "$$tmp/lua.tar.gz" -C "$$tmp"; \
		touch "$$tmp/lua-$(LUA_VERSION)/src/lua.h"; \
		mv "$$tmp/lua-$(LUA_VERSION)" "$(BUILD_DIR)/" || test -f "$@"

$(LUA_LIB): $(LUA_DIR)/lua.h
	@set -e; cd "$(LUA_DIR)"; set --; \
		for source in *.c; do \
			case "$$source" in lua.c|luac.c) continue ;; esac; \
			$(CC) $(ARCHS) $(MIN_VERSION) -DLUA_USE_MACOSX -O2 -Wall -c "$$source"; \
			set -- "$$@" "$${source%.c}.o"; \
		done; \
		libtool -static -o liblua.a "$$@"
	@echo "Built: $(LUA_LIB)"

$(BUILD_DIR)/obj/SpliceKitLua.o: $(LUA_DIR)/lua.h

$(BUILD_DIR)/obj/%.o: Sources/%.m Sources/SpliceKit.h $(VERSION_CONFIG) | $(BUILD_DIR)/obj
	$(CC) $(ARCHS) $(MIN_VERSION) $(OBJC_FLAGS) $(DEBUG_FLAGS) $(VERSION_DEFINE) \
		-I Sources -I $(LUA_DIR) -c $< -o $@

$(BUILD_DIR)/obj/%.o: Sources/%.mm Sources/SpliceKit.h $(VERSION_CONFIG) | $(BUILD_DIR)/obj
	$(CC) $(ARCHS) $(MIN_VERSION) $(OBJCXX_FLAGS) $(DEBUG_FLAGS) $(VERSION_DEFINE) \
		-I Sources -I $(LUA_DIR) -c $< -o $@

$(OUTPUT): $(OBJS) $(LUA_LIB) Sources | $(BUILD_DIR)
	$(CC) $(ARCHS) $(MIN_VERSION) $(FRAMEWORKS) $(LINKER_FLAGS) \
		$(INSTALL_NAME) $(OBJS) $(LUA_LIB) $(CPP_LIBS) -o $(OUTPUT)
	@# -undefined dynamic_lookup lets calls into FCP internals resolve at load time,
	@# but unresolved SpliceKit_* symbols can crash FCP during initialization.
	@undef="$$(nm -u $(OUTPUT) | awk '/^_SpliceKit_/ {print $$NF}' | sort -u)"; \
	if [ -n "$$undef" ]; then \
		echo "ERROR: undefined SpliceKit_* symbols in $(OUTPUT):" >&2; \
		echo "$$undef" | sed 's/^/  /' >&2; \
		echo "Check the implementations in Sources/." >&2; \
		rm -f $(OUTPUT); \
		exit 1; \
	fi
	@echo "Built: $(OUTPUT)"
	@file $(OUTPUT)

$(DSYM): $(OUTPUT)
	dsymutil "$(OUTPUT)" -o "$(DSYM)"
	@echo "Built: $(DSYM)"

clean:
	rm -rf $(BUILD_DIR)

$(VP9_DECODER_EXEC): $(VP9_DECODER_SOURCES) $(VP9_DECODER_INFO) | $(BUILD_DIR)
	@mkdir -p "$(VP9_DECODER_BUNDLE)/Contents/MacOS"
	@cp "$(VP9_DECODER_INFO)" "$(VP9_DECODER_BUNDLE)/Contents/Info.plist"
	$(CC) $(VP9_CFLAGS) $(VP9_FRAMEWORKS) $(VP9_DECODER_SOURCES) $(VP9_LDFLAGS) -o "$(VP9_DECODER_EXEC)"
	@codesign --force --sign - "$(VP9_DECODER_BUNDLE)" >/dev/null
	@echo "Built: $(VP9_DECODER_BUNDLE)"

vp9-prototype: $(VP9_DECODER_EXEC)
	@echo "Staged: $(VP9_BUILD_DIR)"

$(MKV_IMPORT_EXEC): $(MKV_IMPORT_SOURCES) $(MKV_IMPORT_INFO) | $(BUILD_DIR)
	@mkdir -p "$(MKV_IMPORT_BUNDLE)/Contents/MacOS"
	@cp "$(MKV_IMPORT_INFO)" "$(MKV_IMPORT_BUNDLE)/Contents/Info.plist"
	$(CC) $(MKV_CFLAGS) $(MKV_FRAMEWORKS) $(MKV_IMPORT_SOURCES) $(MKV_LDFLAGS) -o "$(MKV_IMPORT_EXEC)"
	@codesign --force --sign - "$(MKV_IMPORT_BUNDLE)" >/dev/null
	@echo "Built: $(MKV_IMPORT_BUNDLE)"

mkv-prototype: $(MKV_IMPORT_EXEC)
	@echo "Staged: $(MKV_BUILD_DIR)"

deploy: $(OUTPUT) tools vp9-prototype mkv-prototype
	@echo "=== Deploying SpliceKit to modded FCP ==="
		@rm -rf "$(FW_DIR)"
		@mkdir -p "$(FW_DIR)/Versions/A/Resources"
	cp $(OUTPUT) "$(FW_DIR)/Versions/A/SpliceKit"
	@cp Documentation/Licenses/Lua.txt "$(FW_DIR)/Versions/A/Resources/Lua-LICENSE.txt"
		@# Create framework symlinks. Use -n so repeated deploys replace the
		@# symlink itself instead of following it into Versions/A.
		@cd "$(FW_DIR)/Versions" && ln -sfn A Current
		@cd "$(FW_DIR)" && ln -sfn Versions/Current/SpliceKit SpliceKit
		@cd "$(FW_DIR)" && ln -sfn Versions/Current/Resources Resources
	@# Create Info.plist if missing
	@test -f "$(FW_DIR)/Versions/A/Resources/Info.plist" || \
		printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.splicekit.SpliceKit</string><key>CFBundleName</key><string>SpliceKit</string><key>CFBundleVersion</key><string>1.0.0</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleExecutable</key><string>SpliceKit</string></dict></plist>' \
		> "$(FW_DIR)/Versions/A/Resources/Info.plist"
	@# Add privacy usage descriptions for transcript, LiveCam, and palette voice dictation.
	@/usr/libexec/PlistBuddy -c "Set :NSSpeechRecognitionUsageDescription 'SpliceKit uses speech recognition for transcript editing and command palette voice dictation inside Final Cut Pro.'" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string 'SpliceKit uses speech recognition for transcript editing and command palette voice dictation inside Final Cut Pro.'" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription 'SpliceKit LiveCam uses the camera for native webcam recording inside Final Cut Pro.'" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 'SpliceKit LiveCam uses the camera for native webcam recording inside Final Cut Pro.'" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription 'SpliceKit uses the microphone for LiveCam capture and command palette voice dictation inside Final Cut Pro.'" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 'SpliceKit uses the microphone for LiveCam capture and command palette voice dictation inside Final Cut Pro.'" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || true
	@# Local network + Bonjour for Vision Pro preview (required on macOS 15+).
	@# `_ivtpreviewclient._tcp` is Apple's service type for Vision Pro remote preview peers.
	@/usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'SpliceKit discovers nearby Vision Pro headsets on your local network to send immersive preview video.'" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :NSBonjourServices array" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :NSBonjourServices: string '_ivtpreviewclient._tcp'" "$(MODDED_APP)/Contents/Info.plist" 2>/dev/null || true
	@# Deploy tools
	@mkdir -p "$(TOOLS_DIR)"
	@$(MAKE) url-import-tools
	@cp $(SWIFT_TOOLS) "$(TOOLS_DIR)/"
	@set -e; for tool in parakeet-transcriber whisper-transcriber; do \
		for config in release apple/Products/Release debug; do \
			binary="Tools/$$tool/.build/$$config/$$tool"; \
			if [ -f "$$binary" ]; then \
				bash Patcher/scripts/copy_transcriber.sh "$$binary" "$(TOOLS_DIR)" "$(FW_DIR)/Versions/A/Resources"; \
				break; \
			fi; \
		done; \
	done
	@# Create plugins directory
	@mkdir -p "$(HOME)/Library/Application Support/SpliceKit/plugins"
	@# Copy Lua example scripts
	@mkdir -p "$(HOME)/Library/Application Support/SpliceKit/lua/auto"
	@rsync -r --ignore-existing --exclude '.*' "Lua Scripts/" "$(HOME)/Library/Application Support/SpliceKit/lua/"
	@# SpliceKit no longer ships BRAW support (use BRAW Toolbox instead). Remove
	@# bundles left behind by older SpliceKit versions so they don't compete with
	@# third-party BRAW Media Extensions.
	@rm -rf "$(MODDED_APP)/Contents/PlugIns/Codecs/SpliceKitBRAWDecoder.bundle" \
		"$(MODDED_APP)/Contents/PlugIns/FormatReaders/SpliceKitBRAWImport.bundle" \
		"$(MODDED_APP)/Contents/Extensions/SpliceKitBRAWRAWProcessor.appex"
	@mkdir -p "$(MODDED_APP)/Contents/PlugIns/Codecs"
	@rm -rf "$(MODDED_APP)/Contents/PlugIns/Codecs/SpliceKitVP9Decoder.bundle"
	@cp -R "$(VP9_DECODER_BUNDLE)" "$(MODDED_APP)/Contents/PlugIns/Codecs/SpliceKitVP9Decoder.bundle"
	@echo "VP9 decoder bundle copied into FCP.app/Contents/PlugIns"
	@mkdir -p "$(MODDED_APP)/Contents/PlugIns/FormatReaders"
	@rm -rf "$(MODDED_APP)/Contents/PlugIns/FormatReaders/SpliceKitMKVImport.bundle"
	@cp -R "$(MKV_IMPORT_BUNDLE)" "$(MODDED_APP)/Contents/PlugIns/FormatReaders/SpliceKitMKVImport.bundle"
	@echo "MKV/WebM format reader copied into FCP.app/Contents/PlugIns"
	@sign_identity=$$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:/ { print $$2; exit } /"Developer ID Application:/ && developer == "" { developer = $$2 } /[0-9]+\) [0-9A-F]+ "/ && first == "" { first = $$2 } END { if (developer != "") print developer; else if (first != "") print first }'); \
	if [ -n "$$sign_identity" ]; then \
		echo "Using signing identity: $$sign_identity"; \
	else \
		sign_identity="-"; \
		echo "No local codesigning identity found; falling back to ad-hoc signing"; \
	fi; \
	if [ -d "$(MODDED_APP)/Contents/PlugIns/Codecs/SpliceKitVP9Decoder.bundle" ]; then \
		codesign --force --sign "$$sign_identity" "$(MODDED_APP)/Contents/PlugIns/Codecs/SpliceKitVP9Decoder.bundle"; \
	fi; \
	if [ -d "$(PROAPP_SUPPORT_FRAMEWORK)" ]; then \
		codesign --force --sign "$$sign_identity" "$(PROAPP_SUPPORT_FRAMEWORK)"; \
	fi; \
	if [ -d "$(REGISTER_PRO_EXTENSION_APP)" ]; then \
		codesign --force --sign "$$sign_identity" --entitlements $(ENTITLEMENTS) "$(REGISTER_PRO_EXTENSION_APP)"; \
	fi; \
	if ! codesign --force --options runtime --sign "$$sign_identity" "$(FW_DIR)" || \
	   ! codesign --force --options runtime --sign "$$sign_identity" --entitlements $(ENTITLEMENTS) "$(MODDED_APP)"; then \
		if [ "$$sign_identity" = "-" ]; then \
			exit 1; \
		fi; \
		echo "Developer signing failed; retrying with ad-hoc signature"; \
		if [ -d "$(MODDED_APP)/Contents/PlugIns/Codecs/SpliceKitVP9Decoder.bundle" ]; then \
			codesign --force --sign - "$(MODDED_APP)/Contents/PlugIns/Codecs/SpliceKitVP9Decoder.bundle"; \
		fi; \
		if [ -d "$(PROAPP_SUPPORT_FRAMEWORK)" ]; then \
			codesign --force --sign - "$(PROAPP_SUPPORT_FRAMEWORK)"; \
		fi; \
		if [ -d "$(REGISTER_PRO_EXTENSION_APP)" ]; then \
			codesign --force --sign - --entitlements $(ENTITLEMENTS) "$(REGISTER_PRO_EXTENSION_APP)"; \
		fi; \
		codesign --force --options runtime --sign - "$(FW_DIR)"; \
		codesign --force --options runtime --sign - --entitlements $(ENTITLEMENTS) "$(MODDED_APP)"; \
	fi
	@codesign --verify --verbose "$(MODDED_APP)" 2>&1
	@echo "=== Deployed successfully ==="

launch: deploy
	@echo "=== Launching modded FCP with SpliceKit ==="
	DYLD_INSERT_LIBRARIES="$(FW_DIR)/Versions/A/SpliceKit" \
		"$(MODDED_APP)/Contents/MacOS/Final Cut Pro" &
	@echo "FCP launched. Check Console.app for [SpliceKit] messages."
	@echo "Connect: python3 Examples/splicekit_client.py system.version"
