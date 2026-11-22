# RAW Tab

Puts Final Cut Pro's own RAW settings in their own **RAW** tab in the inspector, next to Video, Color, Audio and Info, so you don't have to dig through the Info tab and a floating window.

## Why

Grading RAW in Final Cut means opening a floating settings window that sits on top of the viewer and has to be reopened for every clip. In Resolve the RAW settings simply live in a panel. RAW Tab moves the same controls into the inspector, so they follow your selection like any other inspector tab and never cover the picture.

## Supported formats

| Format | Controls shown | Notes |
|---|---|---|
| Media Extension RAW (BRAW via BRAW Toolbox, and other RAW processors) | Final Cut's RAW settings window | |
| ProRes RAW | Final Cut's ProRes RAW settings (Processing, ISO, Exposure Bias, Color Temperature, RAW to Log) | ISO / exposure / temperature only appear when the clip's metadata supports them, as in Final Cut's own window |
| RED (.R3D) | Final Cut's RED RAW settings | Needs RED's Apple Workflow Installer. Click **Load RED RAW Controls** once per session |

- The tab appears only when every selected clip is RAW, and shows the controls for that format.
- Selecting clips of different RAW formats shows a message instead of controls.
- If a format's controls aren't available (for example RED without RED's plugin), the tab says so.
- Final Cut's inspector shows at most five tabs. Native tabs are never pushed out; only another plugin's tab (e.g. Transcript Tab) gives up its slot.
- All controls are Final Cut's own, so changes, undo and saving behave exactly as in the native windows.

To add a format, add one row to `kProviders` in `RawTab.m`.

## Install

```sh
./install.sh raw-tab
```

Then restart Final Cut Pro. Remove with `./install.sh --uninstall raw-tab`. Log: `~/Library/Logs/SpliceKit/raw-tab.log`.

## Credits

By Shubham Pratap ([splicekit-raw-tab](https://github.com/ishubhampratap/splicekit-raw-tab), v2.0.0). Tab plumbing modelled on [Transcript Tab](https://github.com/bcassin/fcp-transcript-tab) (MIT).
