# Inspector Refresh

Fixes Transform controls (Scale, Position, Rotation…) doing nothing on clips you have just dragged into the timeline.

## Why

When you drag a clip (often a still) from the Browser into the timeline and change its Scale in the Inspector, the number changes but the picture doesn't. A freshly dropped clip has no Transform effect of its own yet; Final Cut normally creates one on the first edit, and until then the Inspector shows a shared placeholder. When that step fails, edits go into the placeholder instead of the clip.

## How it works

Right after a drop into the timeline it:

1. Gives each selected video clip that has no Transform of its own a default one (100%, no visible change), using Final Cut's own undoable action.
2. Asks the Inspector to rebuild so its controls point at that Transform.

It doesn't change your selection, and skips clips that already have a Transform and audio-only clips. Each drop adds one invisible "Transform" step to Undo.

## Install

```sh
./install.sh inspector-refresh
```

Then restart Final Cut Pro. Remove with `./install.sh --uninstall inspector-refresh`. Log: `~/Library/Logs/SpliceKit/inspector-refresh.log`.

## Credits

By Shubham Pratap ([splicekit-inspector-refresh](https://github.com/ishubhampratap/splicekit-inspector-refresh), v1.0.0).
