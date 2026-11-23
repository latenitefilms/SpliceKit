# What Is SpliceKit? (The Plain-English Version)

So you've landed on the SpliceKit repo, scrolled through a wall of technical docs, and thought *"...what am I looking at?"* Totally fair. This page is for you.

---

## The Short Version

SpliceKit lets you control Final Cut Pro with text commands and AI instead of clicking buttons and dragging things around. It's also a plugin framework -- so you can build addons and plugins to do all kinds of awesome things that you couldn't normally do with FCP plugins.

---

## OK, But What Does That Actually Mean?

Final Cut Pro is a powerful video editor, but everything in it is manual. You click, drag, scrub, hunt through menus. That's fine for some tasks, but painful for others:

- **Removing silences** from an hour-long interview? That's hundreds of manual cuts.
- **Adding markers** at every beat of a song? Click... click... click...
- **Applying the same color grade** to 50 clips? Hope you like copy-paste.

SpliceKit is really a **collection of plugins** that already adds a ton of quality-of-life features to FCP out of the box, **plus** an AI framework and plugin system that makes it easy to add even more.

Here's some of what's already built in:

- **Silence Removal** -- automatically detects and removes dead air from interviews and podcasts
- **Transcript Editor** -- transcribes your footage, shows you the words, and lets you edit your video by editing the text. Delete a sentence? The video gets cut too. Drag words around? The clips move to match.
- **Command Palette** (Cmd+Shift+P) -- search and run any editing command by typing, instead of hunting through menus
- **Scene Detection** -- automatically finds every cut/scene change in your footage
- **Beat Detection** -- finds beats in music so you can sync edits to the rhythm
- **Batch Export** -- export every clip on your timeline individually, with all effects baked in
- **Social Media Captions** -- auto-generate word-by-word animated captions (TikTok/Reels style)
- **AI Editing** -- describe what you want in plain English and let an AI assistant do the work

And because SpliceKit is a plugin framework, new features get added all the time. You can even **create your own plugins with the help of AI** -- describe what you want a plugin to do, and Claude can help you build it.

---

## How Does It Work? (No CS Degree Required)

Here's the non-technical version:

1. **SpliceKit patches your copy of Final Cut Pro.** It makes a separate copy of FCP in your home folder and adds a small plugin (a "dylib") to it. Your original FCP stays untouched.

2. **When you launch the patched FCP, SpliceKit wakes up inside it.** It can now see and control everything FCP does -- the timeline, your clips, effects, playback, all of it.

3. **You talk to SpliceKit through text.** There are a few ways:
   - A **Command Palette** inside FCP (press Cmd+Shift+P) where you type what you want
   - A **Transcript Panel** for text-based editing
   - An **AI assistant** (like Claude) that can run editing commands for you
   - **Lua scripts** for editing inside Final Cut Pro, or a local JSON-RPC connection from your own app

Think of it like this: FCP is a car with only a steering wheel and pedals. SpliceKit adds voice control and autopilot.

---

## What changes on my Mac?

The patcher creates a second copy of Final Cut Pro in `~/Applications/SpliceKit/`. You can launch either copy. Once you open a library, SpliceKit commands and plugins can edit its projects and media.

SpliceKit uses private Final Cut Pro APIs and changes the sandbox settings on the patched copy. Compatibility depends on the version of Final Cut Pro you run. Keep a backup when trying a new build on an existing library.

---

## Who Is This For?

**Everyone who uses Final Cut Pro.** Seriously. You don't need to be a programmer or a power user to benefit from SpliceKit. Most of the built-in features are things that every editor will appreciate:

- **Casual editors** -- silence removal, transcript editing, and the command palette make everyday editing faster and less tedious
- **Professional editors** -- batch export, scene detection, beat sync, and caption generation save hours on real projects
- **Content creators** -- auto-generate TikTok/Reels-style captions, quickly cut down long recordings, batch-process clips for social media
- **People who want AI-assisted editing** -- describe edits in plain English and let an AI handle the repetitive work for you
- **Developers and tinkerers** -- write Lua or native plugins, connect an MCP client to the bundled Swift server, or call the JSON-RPC bridge from Python and other languages.

The built-in plugins already handle the most common pain points. But if you ever think *"I wish FCP could do X"* -- SpliceKit probably makes it possible, and AI can help you build it even if you've never written a line of code.

---

## How Do I Get Started?

1. Download the DMG from the [SpliceKit releases](https://github.com/latenitefilms/SpliceKit/releases/latest).
2. Drag **SpliceKit** to **Applications**, open it, and click **Patch**.
3. **Launch the patched FCP** from `~/Applications/SpliceKit/`
4. **Try the Command Palette** -- press Cmd+Shift+P and start typing

---

## Still Have Questions?

- Check the [main README](https://github.com/latenitefilms/SpliceKit#readme) for technical details
- Browse the [docs folder](.) for deep dives on specific features
- Open an issue on GitHub if something's unclear -- the community is friendly

You don't need to understand every ObjC class or JSON-RPC endpoint to use SpliceKit. Start with the Command Palette, try the Transcript Editor, and explore from there.
