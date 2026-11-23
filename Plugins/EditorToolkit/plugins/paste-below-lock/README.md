# Paste Below Lock

Pasted clips land below your locked adjustment layers (anything with `lock` in the name), unless they were copied from above a lock: those may stay above it.

## Why

Final Cut pastes a connected clip into the first free lane, which on a finishing timeline is usually *above* the grade layer, so the pasted shot comes out ungraded. Moving it down by hand after every paste is slow and easy to miss.

## How it works

- On copy/cut it records which locks each clip sat above. Copied clips that share a name and duration are told apart by their order in time.
- After the paste, a new clip that ended up above a lock it was *not* above at the source is moved to the lane just above the unlocked clips under the lock.
- If there's no free lane under the lock, only what's actually in the way is pushed up one lane, so the rest of the stacking stays exactly as it was.
- Normally happens inside Final Cut's own Paste action, so the paste and the move are one undo step. If the paste finishes outside that action (for example after a settings sheet), the move is its own undo step right after the paste, and only in the timeline you pasted into.

## Requires

Nothing. Uses the same `lock` naming as Grade Lock.

## Install

```sh
./install.sh paste-below-lock
```

Then restart Final Cut Pro. Remove with `./install.sh --uninstall paste-below-lock`. Log: `~/Library/Logs/SpliceKit/`.
