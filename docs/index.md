---
layout: default
title: SpliceKit Documentation
---

# SpliceKit Documentation

## Getting Started

- [What Is SpliceKit?](WHAT_IS_SPLICEKIT.md) — The plain-English introduction: what SpliceKit does, who it's for, and how editors and developers use it
- [FCP API Reference](FCP_API_REFERENCE.md) — Complete API reference for all key classes, methods, properties, and patterns

## Scripting, Automation & Debugging

- [Lua SDK Reference](LUA_SDK_REFERENCE.md) — The `sk` module and embedded Lua 5.4 engine: actions, RPC methods, ObjC bridge, live coding
- [Lua Scripting Guide](LUA_SCRIPTING_GUIDE.md) — Hands-on tutorial from "Hello World" to multi-step production pipelines
- [Debug Tools Guide](DEBUG_TOOLS_GUIDE.md) — In-process debugging without Xcode: breakpoints, method tracing, property watching, crash handling, expression evaluation, hot plugin loading
- [Runtime Introspection Guide](RUNTIME_INTROSPECTION_GUIDE.md) — Explore FCP's 78,000+ ObjC classes at runtime: methods, properties, ivars, protocols, inheritance, symbol analysis, and IDA Pro export
- [Dialog Automation Guide](DIALOG_AUTOMATION_GUIDE.md) — Detect, inspect, and interact with FCP dialogs, sheets, and alerts programmatically: buttons, text fields, checkboxes, popup menus

## Features & Capabilities

- [Transcript-Based Editing Guide](TRANSCRIPT_EDITING_GUIDE.md) — Text-based video editing via speech transcription: multiple engines (Parakeet, Apple Speech, FCP Native), speaker diarization, silence detection and batch removal, drag-to-reorder, delete-to-cut
- [Command Palette & AI Guide](COMMAND_PALETTE_GUIDE.md) — Quick-access command palette with fuzzy search and Apple Intelligence natural language: 120+ commands, favorites, keyboard navigation
- [Scene & Beat Detection Guide](SCENE_BEAT_DETECTION_GUIDE.md) — Automatic scene change detection via histogram analysis and audio beat/tempo detection for rhythm-based editing and montage creation
- [FlexMusic & Montage Maker Guide](FLEXMUSIC_AND_MONTAGE_GUIDE.md) — Dynamic soundtracks and auto-edit-to-beat montage creation: browse songs, get beat timing, render audio, and assemble montages

## Plugin & Extension Development

- [FxPlug 4 Plugin Development Guide](FXPLUG_PLUGIN_GUIDE.md) — Complete guide to building FxPlug video effects: XPC architecture, Metal rendering, parameters, plugin state, thread safety, color management, onscreen controls, testing, and notarization. Includes the LUT plugin as a reference implementation
- [Workflow Extensions Guide](WORKFLOW_EXTENSIONS_GUIDE.md) — Build extensions that embed inside FCP's UI: ProExtensionHost framework, timeline proxy objects, observer pattern, data exchange, and comparison with SpliceKit
- [Writing an MKV MediaExtension for Final Cut Pro](MKV_MEDIAEXTENSION_GUIDE.md) — Build a modern `MEFormatReader` for Matroska/WebM: plist and entitlements, `MEByteSource`, `METrackReader`, `MESampleCursor`, MKV indexing, sample delivery strategies, codec handoff, and FCP-specific behavior
- [FCPXML Format Reference](FCPXML_FORMAT_REFERENCE.md) — Complete XML interchange format reference: document structure, story elements, assets, timing attributes, effects, transitions, markers, video formats, bundles, and bookmarks
- [Content Exchange Guide](CONTENT_EXCHANGE_GUIDE.md) — Sending and receiving media between apps and FCP: FCPXML, drag-and-drop, Apple Events, growing files, custom share destinations, metadata, roles, and encoder extensions
- [Dragging FCPXML onto the Timeline](TIMELINE_DRAG_DROP_GUIDE.md) — Drag storylines, titles, and other content from a Workflow Extension straight onto the timeline without creating library artifacts

## Technical Deep Dives

- [Caption System Internals](CAPTION_SYSTEM_INTERNALS.md) — How SpliceKit's social caption pipeline works end to end: transcription, grouping, FCPXML generation, paste, and verification
- [FCPXML Direct Paste](FCPXML_DIRECT_PASTE_GUIDE.md) — Pasting FCPXML content straight onto the timeline through FCP's native pasteboard types
- [Beat Detection Internals](BEAT_DETECTION_INTERNALS.md) — How FCP's built-in beat grid is validated, why A/V clips fail, how timing metadata is written, and when to use SpliceKit's external `detect_beats()` tool instead
- [Haptics Internals](FCP_HAPTICS_INTERNALS.md) — Every haptic FCP fires, and how SpliceKit's snapping and playhead haptics hook into them

## Research

Reverse-engineering reports and raw data gathered while building SpliceKit. Useful background, but not required reading.

- [FCP Application Internals](research/FCP_APPLICATION_INTERNALS.md) — FCP's internal architecture: all 53 binaries, 303K+ functions, frameworks, ML pipeline, render engine, and data model
- [FCP Mac vs iPad: Deep Dive Comparison](research/FCP_Mac_vs_iPad_Comparison.md) — Binary-level comparison of Final Cut Pro 12.0 (Mac) and Final Cut Pro 3.0 (iPad)
- [FCP Pasteboard & Media Linking](research/FCP_PASTEBOARD_MEDIA_LINKING.md) — Restoring clips to the timeline with volume/attributes preserved, bypassing the offline media problem
- [Subscribe To Edit](research/FCP_SUBSCRIBE_TO_EDIT.md) — FCP's dormant subscription/churned-mode infrastructure (raw command list in `research/data/`)
- `research/fcp_symbols/` and `research/fcp_defaults_keys.csv` — Extracted action selectors, notifications, defaults keys and Swift symbols (regenerate with `tools/reverse-engineering/dump_fcp_symbols.sh`)

## Maintainers

- [Release Notes](releasenotes.html) — Published via GitHub Pages and linked from the Sparkle appcast
