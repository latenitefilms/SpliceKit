# SpliceKit

[![Release](https://img.shields.io/github/v/release/latenitefilms/SpliceKit)](https://github.com/latenitefilms/SpliceKit/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
[![Discord](https://img.shields.io/badge/Discord-FCP%20Cafe-5865F2?logo=discord&logoColor=white)](https://discord.com/invite/HD3FPc4Azu)
[![Docs](https://img.shields.io/badge/docs-splicekit.fcp.cafe-0A84FF)](https://splicekit.fcp.cafe)

---

This is a **fork** of the official [SpliceKit repository](https://github.com/elliotttate/SpliceKit) created by [elliotttate](https://github.com/elliotttate/) for the FCP Cafe community.

---

**Final Cut Pro, unlocked. A Command Palette, MCP server, and an open plugin framework to do almost anything.**

| 🎹 Command Palette | 🤖 MCP Server | 🧩 Plugin Framework |
|---|---|---|
| Hit `Cmd+Shift+P` and type what you want. Apple Intelligence runs it. | Connect an MCP client to edit your timeline and use tools from installed plugins. | Every built-in feature is just an example plugin. You (or an AI) can ship more. |

> **Editor? Start here.** The [official SpliceKit site](https://splicekit.fcp.cafe) and the [FAQ](https://splicekit.fcp.cafe/faq/) are the friendliest way in. Questions, help, or feature requests? Join the SpliceKit channels on the [FCP Cafe Discord](https://discord.com/invite/HD3FPc4Azu). Bug reports: [open a GitHub issue](https://github.com/latenitefilms/SpliceKit/issues).
>
> Can't wait to see what you do with it. 🥳

---

## The Three Pillars

### 🎹 1. The Command Palette

*One keystroke to anything.*

Hit **Cmd+Shift+P** inside the patched FCP. Fuzzy-search 100+ built-in editing actions — blade, trim, color, speed, markers, effects, transitions, export — or type plain English and let **Apple Intelligence** (on-device, private) figure out what you meant.

[![Command Palette Demo](https://img.youtube.com/vi/Q4GjHmmUISw/maxresdefault.jpg)](https://youtu.be/Q4GjHmmUISw)

#### Try saying…

- *"add markers every 5 seconds"*
- *"slow this clip to half speed"*
- *"blade at every scene change"*
- *"remove all the silences"*
- *"add a cross dissolve"*

> No more menu hunting. No more memorizing shortcuts. No cloud.

---

### 🤖 2. The MCP Server

SpliceKit’s Swift MCP server provides 189 built-in tools, 10 resources and seven editing prompts. Connect **Claude Code**, **Claude Desktop**, or another MCP client to request edits like these.

- *"cut this 40-minute interview down to its best moments"*
- *"remove the silences from this podcast, add captions, and export"*
- *"assemble a rough cut from these clips, synced to the beat of this song"*

The server sends commands to the SpliceKit bridge inside Final Cut Pro. It can inspect clips, blade, retime, color-correct, apply effects and render using the editor’s own methods.

#### Reusing an editing workflow

A plugin can register a named editing command with SpliceKit. The Swift server discovers those commands when the client first lists its tools. After you install or update a plugin, call `reload_plugin_tools` to refresh the list for the current session.

---

### 🧩 3. The Plugin Framework

*Everything is a plugin.*

SpliceKit isn't a feature list — it's a platform. Once the SpliceKit dylib is loaded into Final Cut Pro, the entire ObjC runtime (78,000+ classes, including all private APIs) is open for plugins to use.

#### What a plugin can do

- Add new panels and windows inside FCP
- Put buttons on the toolbar, menu, or Enhancements menu
- Register commands in the Command Palette
- Expose new tools over the MCP server
- Hook into timeline events, selection changes, and playback
- Ship custom Motion templates, FxPlug effects, and Workflow Extensions
- Use Lua or a native library for an in-process plugin. External tools can use any language that speaks JSON-RPC.

#### And you can ask an AI to build one

Describe the editing workflow you want and give your coding assistant the project’s [contributor guide](AGENTS.md) and [Editor Toolkit examples](Plugins/EditorToolkit/README.md).

---

## Example Plugins (What Ships in the Box)

Every one of these is a plugin. They're bundled so you can use SpliceKit the day you install it, and they double as working examples for anyone building their own.

### Text-Based Editor
Transcribe every clip on your timeline with on-device speech recognition (NVIDIA Parakeet — 25 languages, no cloud, with speaker diarization). Click a word to jump there. Select a sentence, hit Delete, and the video gets cut to match. Drag words to reorder clips. Export as SRT or plain text.

[![Text-Based Editor Demo](https://img.youtube.com/vi/JxxDSH4Ly0I/maxresdefault.jpg)](https://www.youtube.com/watch?v=JxxDSH4Ly0I)

### Audio Mixer
Mix by **role**, not clip-by-clip. Drop a compressor, EQ, or reverb on your Dialogue bus and every clip tagged Dialogue inherits it — past, present, and future. Retag a clip's role and it instantly picks up the new bus's processing. Set volumes, solo, and mute per role from one panel.

[![Audio Mixer Demo](https://img.youtube.com/vi/k_HL35lXFOA/maxresdefault.jpg)](https://www.youtube.com/watch?v=k_HL35lXFOA)

### Sections
A color-coded section bar above the timeline that shows the shape of your edit at a glance. Name sections, color them, jump between them in one click — perfect for long-form edits, podcasts, multi-chapter projects, or anywhere you want to see structure without scrubbing.

[![Sections Demo](https://img.youtube.com/vi/plirvqHe6o0/maxresdefault.jpg)](https://youtu.be/plirvqHe6o0)

### Silence Remover
Point it at an interview or podcast recording and it finds and cuts every silent pause. Configurable threshold, minimum duration, and padding. Pure Apple-native AVFoundation + Accelerate under the hood.

### Social Media Captions
Generate word-by-word highlighted, animated captions in 13 built-in styles (Bold Pop, Neon Glow, Karaoke, Typewriter, Bounce, and more). Captions land directly on your timeline as editable Motion titles.

### Scene Detection
Finds every shot change in your footage using vImage histogram comparison. Add markers, blade the timeline, or both.

### Beat Detection & Song Cut
Pulls BPM, beats, bars, and song sections from any music file. Hand **Song Cut** a music track and a folder of footage and get back a beat-synced music video on your timeline, with selectable pacing (natural, medium, fast, aggressive) or custom step weights.

### LiveCam
A built-in webcam booth that records straight to your library or active timeline. Live preview with color adjustments, audio meter, and a subject-lift green-screen matte that works on people *and* objects (macOS 14+). Pick "Transparent" as the green-screen color and LiveCam writes ProRes 4444 with a real alpha channel.

### URL Import
Paste a YouTube, Vimeo, or Twitter link and pull it into your library as a real clip. Auto-discovers `yt-dlp` and `ffmpeg` from your shell PATH.

### Batch Export
One command, every clip on your timeline exports as its own file — all effects, color grades, and transitions baked in.

### Native VP9 and MKV/WebM Support
The source checkout includes a VP9 decoder and an MKV/WebM format reader for development. Developers can install these prototypes into an existing patched copy with `make -f Scripts/Makefile deploy`.

For Blackmagic RAW (`.braw`), use [BRAW Toolbox](https://brawtoolbox.io) — SpliceKit no longer includes its own BRAW support.

### Dual Timelines, FlexMusic, Montage Maker, OpenTimelineIO exchange, Lua REPL, in-process debugger…
…and more. Every one of them is code in `Sources/` you can read, fork, or gut for parts.

---

## Install in 60 Seconds

The SpliceKit patcher requires a paid LateNite app, such as BRAW Toolbox or Marker Toolbox, installed from the Mac App Store. If you need to install one, the patcher shows the list of eligible apps. Return to the patcher after installation or click **Check Again** to continue. [Browse LateNite apps on the Mac App Store](https://apps.apple.com/au/developer/latenite-films-pty-ltd/id1652018641).

[![Installation Guide](https://img.youtube.com/vi/NxbInKlXQVs/maxresdefault.jpg)](https://www.youtube.com/watch?v=NxbInKlXQVs)

1. Download **SpliceKit** from the [latest release](https://github.com/latenitefilms/SpliceKit/releases/latest)
2. Open the DMG, drag **SpliceKit** to **Applications**, and open the app
3. Select your Final Cut Pro installation and click **Continue**

The patcher copies Final Cut Pro to `~/Applications/SpliceKit/` and installs SpliceKit in that copy. The MCP server ships inside the patcher app.

Once done, click **Launch FCP** in the patcher, or open the new copy from `~/Applications/SpliceKit/`. Press **Cmd+Shift+P** to open the Command Palette and you're off.

From a source checkout, open `Patcher/SpliceKit.xcodeproj` and run the **SpliceKit** scheme. The same Swift app handles installation, updates, rebuilds, and removal.

**Updating SpliceKit.** Choose **SpliceKit → View Releases on GitHub** to find new versions. Download the new DMG, quit the patcher and replace `SpliceKit.app` in Applications. Open the new patcher and choose **Update SpliceKit** if it offers to update your Final Cut Pro copy. [GitHub Releases](https://github.com/latenitefilms/SpliceKit/releases)

---

## Connect It to Claude (or any MCP client)

In the patcher, choose **Set Up MCP for a Project…** to create a `.mcp.json` pointing to the bundled Swift server. You can also configure your client directly. The server communicates over standard input and output. Tool discovery works with Final Cut Pro closed. Open the patched copy of Final Cut Pro to use editing tools.

```json
{
  "mcpServers": {
    "splicekit": {
      "command": "/Applications/SpliceKit.app/Contents/Resources/mcp/splicekit-mcp"
    }
  }
}
```

**Building in Xcode.** Build the `SpliceKit` scheme in `Patcher/SpliceKit.xcodeproj`. The build also writes `build/mcp/splicekit-mcp` in the checkout. The included `.mcp.json` uses that executable. For clients started elsewhere, set `command` to its absolute path. From Terminal, `make -f Scripts/Makefile mcp-setup` builds the same server and `make -f Scripts/Makefile mcp-doctor` checks the executable, client configuration, and bridge.

**Optional OpenTimelineIO adapters.** FCPXML import and export and single-timeline OTIO JSON import run natively. Other interchange operations, including OTIO export, EDL, and AAF, use an external adapter. The checkout includes `MCP/otio-adapter`. Install OpenTimelineIO and the format adapters in `~/.venvs/splicekit-otio`, or set `SPLICEKIT_OTIO_PYTHON` to the interpreter for an existing environment. To use it from the installed app and Final Cut Pro’s menus, link the checkout executable at `~/.local/bin/splicekit-otio-adapter`. An MCP client can also set `SPLICEKIT_OTIO_ADAPTER` to the executable’s absolute path. Older MCP client configurations that point to `server.py` inside the app should use `splicekit-mcp` as shown above.

**Optional Gemma engine.** Start a compatible local Gemma model server at `http://localhost:8080` before selecting Gemma in the command palette. SpliceKit connects over HTTP.

**Developer tools.** The checkout retains the 220-tool Python MCP entry point, including 31 additional developer commands. To use it, install `MCP/requirements.txt` in a virtual environment, launch that interpreter as the MCP command, and pass the absolute path to `MCP/server.py` as its argument. The Swift editing tools accept the same arguments. Some return their results as JSON instead of formatted text.

---

## What the patcher changes

The patched copy and the App Store copy of Final Cut Pro can open the same libraries. Timeline commands and plugins perform real edits in the library you have open. SpliceKit uses private Final Cut Pro APIs, so a Final Cut Pro update can require a compatible SpliceKit build.

SpliceKit writes its logs to `~/Library/Logs/SpliceKit/`. macOS keeps Final Cut Pro crash reports in `~/Library/Logs/DiagnosticReports/`. The patcher’s **Share Logs** button uploads the latest reports to filebin.net when you choose to share them.

For a walkthrough with screenshots, see the [SpliceKit installation guide](https://splicekit.fcp.cafe/installation/).

---

## Building Plugins

If you're here to build things, this is the section for you.

### What's actually happening

SpliceKit injects a dynamic library into a re-signed copy of Final Cut Pro. Once loaded:

- The full ObjC runtime is exposed (78,000+ classes including all private APIs)
- A JSON-RPC 2.0 server listens on `127.0.0.1:9876`
- An MCP server translates tool calls into bridge RPCs
- Flexo, Ozone, TimelineKit, LunaKit, Helium, ProCore — all of FCP's internal frameworks — are reachable via direct `objc_msgSend`
- Crash points around CloudKit / ImagePlayground (which need entitlements a re-signed app doesn't have) are swizzled out

```
┌─────────────────────────────────────────────┐
│  Final Cut Pro (patched copy)               │
│  ┌───────────────────────────────────────┐  │
│  │  SpliceKit.framework (LC_LOAD_DYLIB)  │  │
│  │  ├── Command Palette                  │  │
│  │  ├── JSON-RPC bridge on :9876         │  │
│  │  ├── Plugin loader (hot-reload)       │  │
│  │  └── your plugins here                │  │
│  └───────────┬───────────────────────────┘  │
│              │ objc_msgSend                  │
│  ┌───────────▼───────────────────────────┐  │
│  │  Flexo / Ozone / TimelineKit / ...    │  │
│  └───────────────────────────────────────┘  │
└──────────────────────┬──────────────────────┘
                       │ TCP :9876
        ┌──────────────▼──────────────┐
        │  Swift MCP server or other  │
        │  JSON-RPC clients           │
        └─────────────────────────────┘
```

### Ways to build

- **Native plugins** — see [EditorToolkit](Plugins/EditorToolkit/README.md) for Objective-C plugins and their build settings.
- **Lua, inside FCP** — Ctrl+Opt+L opens a REPL with the `sk` module. Browse the [bundled Lua examples](Lua%20Scripts/examples).
- **Direct JSON-RPC** — any language with a TCP socket can use the bridge. To read its version, run `echo '{"jsonrpc":"2.0","method":"system.version","id":1}' | nc 127.0.0.1 9876`.
- **MCP tools** — expose your plugin's capabilities as MCP tools and any AI client can drive them.
- **Open a PR to SpliceKit itself** — if the thing you built is useful to other editors, send it upstream. The bundled "features" (Text-Based Editor, Silence Remover, LiveCam, Song Cut, etc.) all started as plugins. Fork the repo, drop your plugin in `Plugins/` or `Sources/`, and open a [pull request](https://github.com/latenitefilms/SpliceKit/pulls) — community plugins are how SpliceKit grows.

### Key FCP internals worth knowing

| Class | Methods | Purpose |
|-------|---------|---------|
| `FFAnchoredTimelineModule` | 1435 | Primary timeline controller |
| `FFAnchoredSequence` | 1074 | Timeline data model |
| `FFLibrary` / `FFLibraryDocument` | 203 / 231 | Library management |
| `FFEditActionMgr` | 42 | Edit command dispatcher |
| `FFPlayer` | 228 | Playback engine |
| `PEAppController` | 484 | App controller |

| Prefix | Framework | Classes |
|--------|-----------|---------|
| FF | Flexo — core engine, timeline, editing | 2849 |
| OZ | Ozone — effects, compositing, color | 841 |
| PE | ProEditor — app controller, windows | 271 |
| LK | LunaKit — UI framework | 220 |
| TK | TimelineKit — timeline UI | 111 |
| IX | Interchange — FCPXML import/export | 155 |

### Build from source

```bash
git clone https://github.com/latenitefilms/SpliceKit.git
cd SpliceKit
open Patcher/SpliceKit.xcodeproj
```

The first build resolves the Swift packages and downloads Lua 5.4.9. It verifies the Lua archive’s SHA-256 and links Lua into the universal SpliceKit dylib. Subsequent builds reuse the copy under `build/`. To build offline, cache the resolved Swift packages and supply a local Lua archive with the Xcode build setting `LUA_URL=file:///absolute/path/to/lua-5.4.9.tar.gz`.

Build the **SpliceKit** scheme in Xcode. Both Debug and Release build without Python. Release builds the MCP server and the transcription helpers for Apple silicon and Intel. Xcode invokes `Scripts/Makefile` for the bridge and companion executables. Run the native server tests with `swift test --package-path MCP` and the optional development suite with `python3 -m unittest discover -s Tests`. The programs in `Tests/live/` exercise a running Final Cut Pro.

Set **Version** and **Build** under the SpliceKit target’s **General → Identity** settings in Xcode. The app and native bridge use Version. Increase Build for each release.

For a public release, choose **Product → Archive** in Xcode and export the app through Organizer. Publish the signed, notarized DMG on GitHub Releases with the version’s notes from the [changelog](CHANGELOG.md).

---

## Community

- **Questions, help, feature requests**: [FCP Cafe Discord](https://discord.com/invite/HD3FPc4Azu) (SpliceKit channels)
- **Bug reports**: [GitHub Issues](https://github.com/latenitefilms/SpliceKit/issues)
- **Features, videos, FAQ**: [splicekit.fcp.cafe](https://splicekit.fcp.cafe)

There's a long tradition of community modding projects getting adopted back into the official products they extend. If SpliceKit helps push Final Cut Pro forward, everyone wins.

---

## License

[MIT](LICENSE.md). Use it, modify it, ship your own plugins with it.

Onwards & upwards 🥳
