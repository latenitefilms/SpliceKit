# Editor Toolkit for SpliceKit

Small native SpliceKit plugins for Final Cut Pro. Each one fixes a specific friction from day-to-day finishing work on fashion films, luxury commercials and branded spots, shot on a Blackmagic Cinema Camera 6K in Blackmagic RAW.

Install all of them, a themed preset, or any single plugin. Each plugin installs and runs on its own, but a few are meant to be used together: Grade Lock Skim pairs with Grade Lock, and RAW Multi, RAW Gyro and Shortcuts' Edit RAW Properties work best with RAW Tab installed (`install.sh` says so when you leave the partner out).

## The thinking behind it

- **Final Cut stays Final Cut.** Every plugin runs through Final Cut's own actions (its Paste, Blade, Copy, inspector checkbox, Command Editor, FCPXML importer). Undo, multi-clip edits and shortcuts keep working the way an editor expects. Nothing adds a parallel UI where a native one already exists.
- **Borrow what Resolve gets right.** Many of these exist because a Resolve habit had no Final Cut equivalent: RAW settings in a panel, editing RAW across a multi-selection, gyro stabilisation as one control, flip buttons, a playback FPS readout, targeting the clip you can see.
- **Finishing timelines are layered.** Grade, film emulation, grain and letterbox adjustment layers sit on top of everything. One naming rule (put `lock` in the clip name) drives several plugins: those layers can't be selected by accident, the inspector looks through them, pastes land under them, and Blade/Copy skip them.
- **Small, single-purpose, removable.** One feature per plugin and one source file per plugin. Each logs to `~/Library/Logs/SpliceKit/` and falls back to doing nothing if the Final Cut internals it needs aren't there.

## Plugins

| Plugin | What it does | Preset |
|---|---|---|
| [RAW Tab](plugins/raw-tab) | RAW settings (Media Extension RAW, ProRes RAW, RED) as their own inspector tab | `@raw` |
| [RAW Multi](plugins/raw-multi) | RAW controls stay editable across a multi-clip selection | `@raw` |
| [RAW Gyro Presets](plugins/raw-gyro) | One-click gyro stabilisation presets plus a single strength dial | `@raw` |
| [Shortcuts](plugins/shortcuts) | Command Editor commands: Edit RAW Properties, Toggle Stabilization, Zoom to Fit toggle, Show Video/Info Inspector | `@raw` |
| [Grade Lock](plugins/grade-lock) | Clips named `…lock…` can't be selected without Option | `@lock` |
| [Grade Lock Skim](plugins/grade-lock-skim) | The inspector and skimmer look through locked layers | `@lock` |
| [Paste Below Lock](plugins/paste-below-lock) | Pasted clips land under locked adjustment layers | `@lock` |
| [Topmost Clip Editing](plugins/topmost) | With nothing selected, Blade/Copy act on the top visible clip (off until you turn it on in View) | `@lock` `@editing` |
| [Batch Sync Audio](plugins/audio-sync) | Waveform-sync many clips to external recordings in one go | `@editing` |
| [XML Clips](plugins/xml-clips) | After an XML import, the timeline's clips appear in the browser | `@editing` |
| [Flip](plugins/flip) | Flip H/V buttons and an Image Orientation menu in Transform | `@editing` |
| [Inspector Refresh](plugins/inspector-refresh) | Scale/Position work on clips you just dropped into the timeline | `@editing` |
| [Playback Frame Rate](plugins/fps-meter) | Live delivered-FPS and dropped-frame readout in the viewer | `@monitoring` |
| [Workspace Collapse](plugins/workspace-collapse) | The timeline takes the full height in a vertical workspace | `@workspace` |

Each folder has its own README covering what the plugin does, why it exists, how it works and what it needs.

## Install

Requirements: Apple Silicon Mac, Final Cut Pro with SpliceKit running, and Apple's command line tools (`xcode-select --install`).

```sh
cd Plugins/EditorToolkit
./install.sh --list            # see everything
./install.sh --all             # install every plugin
./install.sh @raw              # install a preset
./install.sh raw-tab flip      # install individual plugins
./install.sh --uninstall flip  # remove one
```

Restart Final Cut Pro afterwards. Plugins are built from source, ad-hoc signed, and copied to `~/Library/Application Support/SpliceKit/plugins/<name>/` (each with its `plugin.json`).


## Tested on

Written and used on Final Cut Pro 12.4 (build 454072) with SpliceKit 3.3.9, macOS 27.2, Apple Silicon.

In this repository, on Final Cut Pro 13.0 (and Creator Studio 13.0 for the classes and methods): every private class and method the plugins use exists, and all 14 build and load into a running Final Cut. Exercised in Final Cut 13.0: Topmost, Paste Below Lock, XML Clips and Inspector Refresh. Not yet exercised there: RAW Tab, RAW Multi and RAW Gyro with RAW media (BRAW, ProRes RAW, RED), the Playback Frame Rate readout during playback, Batch Sync Audio's sync, Flip, Shortcuts' commands (they register), Grade Lock, Grade Lock Skim and Workspace Collapse (Vertical Workspace).

The plugins rely on private Final Cut classes, so a Final Cut update can break any of them. Each checks for what it needs at load time and logs what it found.

## Layout

```
Plugins/EditorToolkit/
├── install.sh                 build / install / uninstall
└── plugins/<name>/
    ├── <Source>.m             the whole plugin, one file
    ├── plugin.json            SpliceKit manifest
    ├── build.env              source, product and frameworks for install.sh
    └── README.md
```

## Changes in this repository

Imported from [ishubhampratap/SpliceKit `editor-toolkit`](https://github.com/ishubhampratap/SpliceKit/tree/editor-toolkit) (upstream PR #100) after review, with these changes:

- **Topmost** is off until you turn it on, and only redirects commands you issue (menu, shortcut, toolbar). SpliceKit's own programmatic `blade:`/`copy:` calls (transcript editing, `bladeAtTimes`) always get Final Cut's normal behaviour.
- **Playback Frame Rate** holds viewer destinations weakly, so closing a viewer (full screen, Event Viewer, closing a project) can't crash Final Cut.
- **XML Clips** only acts on a timeline the import itself created, opened within 20 seconds of it, instead of whatever project you open in the next 10 minutes, and tells sources apart by their media rather than their name.
- **Grade Lock Skim** looks up `SpliceKit_getActiveTimelineModule` by its real (C) symbol name, so "show the clip below" works.
- Leftover in-process test hooks (Batch Sync Audio's `SKAS` notifications, which could apply a sync without the review panel; Flip's and Workspace Collapse's test notifications; the FPS meter's debug dump) are removed.
- **Workspace Fix** isn't included: it disabled parts of SpliceKit's dual-timeline support from outside the core. The crash it worked around should be fixed in SpliceKit itself.
- `install.sh --uninstall` only removes plugins this toolkit ships. The prebuilt download zips and `--package` were dropped; plugins are built from this source.

## Credits

By Shubham Pratap. RAW Tab's inspector-tab plumbing is modelled on [Transcript Tab](https://github.com/bcassin/fcp-transcript-tab) (MIT). The toolkit from upstream PR #100 is MIT licensed, like SpliceKit. RAW Tab v2.0.0 and Inspector Refresh come from separate repositories ([splicekit-raw-tab](https://github.com/ishubhampratap/splicekit-raw-tab), [splicekit-inspector-refresh](https://github.com/ishubhampratap/splicekit-inspector-refresh)) that don't declare a license.
