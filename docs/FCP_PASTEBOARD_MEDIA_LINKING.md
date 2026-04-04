# FCP Pasteboard & Media Linking: Restoring Clips with Attributes

## The Problem

When building an extension that saves SFX (or any clips) from the FCP timeline and later restores them, you hit a fundamental conflict in how Final Cut Pro handles clipboard data:

**Path A — Paste via file URL**: FCP accepts the file and places the clip on the timeline, but **ignores saved volume, effects, and other attributes**. It treats the URL as a fresh media import and creates a new clip with default properties.

**Path B — Paste stored FCP clipboard data**: The native clipboard data has volume, effects, and attributes baked in, but FCP **rejects it if the referenced media file isn't already linked in the project**. The clip appears offline.

The root cause is that FCP's native clipboard format stores **media references** (document IDs, parent object IDs, persistent IDs), not the actual media. At paste time, FCP resolves these references against the current project library. If the media isn't linked, resolution fails.

---

## How FCP's Pasteboard System Works

### Three-Layer Architecture

1. **IXXMLPasteboardType** (Interchange framework) — Defines UTI type strings for FCPXML data on the pasteboard. Class methods like `current`, `previous`, `generic`, `string` each return a UTI string for a specific FCPXML version.

2. **FFPasteboardItem** (Flexo framework) — The serialized clipboard item. Implements `NSPasteboardWriting`, `NSPasteboardReading`, and `NSSecureCoding`. Stores encoded clip data as a property list.

3. **FFPasteboard** (Flexo framework) — The coordinator with 76 methods. Reads/writes `FFPasteboardItem` objects to/from the underlying `NSPasteboard`.

### Native Clipboard Data Format

When FCP writes clips to the pasteboard, `FFPasteboardItem` serializes them as an `NSPropertyList` dictionary with these keys:

| Key | Type | Purpose |
|-----|------|---------|
| `ffpasteboardobject` | NSData | FFCoder-encoded clip objects (the actual clip data with all attributes) |
| `ffpasteboardcopiedtypes` | NSDictionary | Metadata about what was copied (`anchoredObject`, `edit`, `media`, etc.) |
| `ffpasteboarddocumentID` | NSString | Source library's unique identifier |
| `ffpasteboardparentobjectID` | NSString | Parent container's persistent ID |
| `ffpasteboardoptions` | NSDictionary | Paste options |
| `kffmodelobjectIDs` | NSArray | Object identifiers for lazy/promise resolution |

The `ffpasteboardobject` data is encoded by `FFCoder.encodeData:options:error:` with `FFXMLAssetUsageKey = 0`.

### The UTI Type

FCP's native pasteboard UTI is `com.apple.flexo.proFFPasteboardUTI` (Pro version). There's a separate consumer/iMovie variant. A promise UTI also exists for deferred data loading.

### Readable Types (What FCP Accepts on Paste)

FCP's `+[FFPasteboard readableTypes]` registers these types in order:

1. `FFPasteboardUTI` (native FCP format — pro or consumer)
2. `NSPasteboardTypeURL` (file URLs)
3. `[IXXMLPasteboardType all]` (all FCPXML version UTIs)
4. `NSFilePromiseReceiver` readable types

---

## The Two Paste Paths (Critical Discovery)

FCP's core paste decoder (`_newObjectsWithProjectCore:assetFlags:fromURL:options:userInfoMap:`) has **two completely separate code paths**:

### Path 1: Native FFPasteboardItem

```
If pasteboard contains FFPasteboardUTI type:
  1. Read FFPasteboardItem objects from pasteboard
  2. Resolve documentID against open library documents
  3. Decode via FFCoder → FCP model objects
  4. If documentID doesn't match current library → OFFLINE / FAIL
```

This is why your stored clipboard data fails — the `documentID` and `parentObjectID` reference a library state that no longer matches, or the media asset isn't registered in the current project.

### Path 2: FCPXML on Pasteboard

```
If pasteboard does NOT contain FFPasteboardItem
  BUT pasteboard contains XML (IXXMLPasteboardType):
    1. Create FFXMLTranslationTask from pasteboard data
    2. Validate contentType == sequence/clip data
    3. Create FFXMLImportOptions:
       - incrementalImport = YES (adds to existing library)
       - conflictResolutionType = 3 (merge, don't replace)
       - Target = current project's defaultMediaEvent
    4. Run importClipsWithOptions:taskDelegate:
    5. MEDIA IS AUTOMATICALLY IMPORTED from src= URLs
    6. Return imported clips as FigTimeRangeAndObject items
```

**This is the key**: when FCP finds FCPXML on the pasteboard instead of native `FFPasteboardItem` data, it runs the **full XML import pipeline** — which handles media file linking automatically.

---

## Solution 1: FCPXML Pasteboard (Recommended)

Write FCPXML data directly to `NSPasteboard` using `IXXMLPasteboardType` UTI strings. FCP's XML paste path will import the media and preserve all attributes declared in the XML.

### Step 1: Discover the UTI Strings at Runtime

```objc
Class IXType = objc_getClass("IXXMLPasteboardType");
NSString *currentType  = [IXType performSelector:@selector(current)];
NSString *genericType  = [IXType performSelector:@selector(generic)];
NSString *stringType   = [IXType performSelector:@selector(string)];
NSArray  *allTypes     = [IXType performSelector:@selector(all)];

NSLog(@"Current: %@", currentType);
NSLog(@"Generic: %@", genericType);
NSLog(@"String:  %@", stringType);
NSLog(@"All:     %@", allTypes);
```

Cache these strings — they won't change during a session.

### Step 2: Build FCPXML with Asset + Attributes

```objc
NSString *fcpxml = [NSString stringWithFormat:
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    @"<!DOCTYPE fcpxml>\n"
    @"<fcpxml version=\"1.11\">\n"
    @"  <resources>\n"
    @"    <format id=\"r0\" frameDuration=\"1/24s\" width=\"1920\" height=\"1080\"/>\n"
    @"    <asset id=\"r1\" src=\"%@\" hasAudio=\"1\" hasVideo=\"0\"\n"
    @"           audioSources=\"1\" audioChannels=\"2\" audioRate=\"48000\"/>\n"
    @"  </resources>\n"
    @"  <library>\n"
    @"    <event name=\"Restored SFX\">\n"
    @"      <project name=\"_paste_temp\">\n"
    @"        <sequence format=\"r0\" duration=\"%@\">\n"
    @"          <spine>\n"
    @"            <asset-clip ref=\"r1\" name=\"%@\" duration=\"%@\"\n"
    @"                        start=\"0s\" format=\"r0\">\n"
    @"              <adjust-volume amount=\"%@dB\"/>\n"
    @"            </asset-clip>\n"
    @"          </spine>\n"
    @"        </sequence>\n"
    @"      </project>\n"
    @"    </event>\n"
    @"  </library>\n"
    @"</fcpxml>",
    fileURL,          // file:///path/to/sfx.wav
    durationStr,      // e.g., "240/24s" or "10s"
    clipName,         // display name
    durationStr,      // clip duration
    volumeStr];       // e.g., "-6" for -6dB
```

FCPXML supports a wide range of attributes:

```xml
<!-- Volume -->
<adjust-volume amount="-6dB"/>

<!-- Pan -->
<adjust-panner mode="stereo" amount="-50"/>

<!-- Effects -->
<filter-video ref="r2" name="Gaussian Blur">
    <param name="Amount" key="9999/gaussianBlur/radius" value="10"/>
</filter-video>

<!-- Transform -->
<adjust-transform position="100 50" scale="1.2 1.2" rotation="15"/>

<!-- Opacity / Blend Mode -->
<adjust-blend amount="0.75" mode="multiply"/>
```

### Step 3: Write to Pasteboard

```objc
NSData *xmlData = [fcpxml dataUsingEncoding:NSUTF8StringEncoding];
NSPasteboard *pb = [NSPasteboard generalPasteboard];
[pb clearContents];
[pb setData:xmlData forType:currentType];
```

### Step 4: Trigger Paste

Either let the user Cmd+V, or programmatically:

```objc
id timelineModule = /* get active FFAnchoredTimelineModule */;
[timelineModule performSelector:@selector(paste:) withObject:nil];
```

### What Happens Internally

1. FCP checks for `FFPasteboardItem` → not found
2. Checks for XML types via `containsXML` → found (your FCPXML data)
3. `FFXMLTranslationTask` reads the XML, tries types in order: `current`, `previous`, `previousPrevious`, `generic`, falls back to `string`
4. Parses with `FFXML.importXMLData:version:contentType:error:`
5. Creates `FFXMLImportOptions` with `incrementalImport:YES`, `conflictResolutionType:3`
6. Sets target to the current project's `defaultMediaEvent`
7. Runs `importClipsWithOptions:taskDelegate:` — this resolves the `src=` URL, imports the media file, creates `FFAsset` entries
8. Returns imported clips ready for timeline insertion

### Advantages

- Single operation: media import + attribute restoration in one paste
- No offline clips — FCP handles media linking through its standard XML import pipeline
- Volume, effects, transforms, roles all survive via FCPXML attributes
- Incremental import — merges into existing project, doesn't create a new library
- Conflict resolution set to merge — safe for repeated operations

### Limitations

- Only attributes expressible in FCPXML are preserved (covers most common ones)
- Very complex custom effect parameters may require additional FCPXML authoring
- The paste creates a temporary project/event structure; clips land in the timeline but an event may also appear in the library sidebar

---

## Solution 2: Two-Step Import Then Paste (Fallback)

If you need to preserve the exact native clipboard data (with complex attributes that FCPXML can't express), import the media first so the native paste succeeds.

### Step 1: Import Media to Library

Import the file into the current project's library so FCP creates an `FFAsset` for it:

```objc
// Option A: Via FFPasteboard with URL
NSPasteboard *tempPB = [NSPasteboard pasteboardWithUniqueName];
[tempPB clearContents];
[tempPB writeObjects:@[[NSURL fileURLWithPath:sfxFilePath]]];

Class FFPasteboardClass = objc_getClass("FFPasteboard");
id ffpb = [[FFPasteboardClass alloc]
    performSelector:@selector(initWithPasteboard:) withObject:tempPB];

id timelineModule = /* active timeline module */;
id sequence = [timelineModule performSelector:@selector(sequence)];

// This imports the media into the project library
[ffpb performSelector:@selector(newMediaWithSequence:fromURL:options:)
           withObject:sequence withObject:nil withObject:nil];
```

```objc
// Option B: Via FCPXML file import (more reliable)
// Write a minimal FCPXML to a temp file, then:
id appController = [NSApp performSelector:@selector(delegate)];
NSURL *xmlURL = /* temp FCPXML file URL */;
[appController performSelector:@selector(openXMLDocumentWithURL:bundleURL:display:sender:)
                    withObject:xmlURL withObject:nil withObject:@NO withObject:nil];
```

### Step 2: Patch documentID (If Needed)

Your stored clipboard data may have a `documentID` from a different library session. Patch it:

```objc
// Read the current library's unique identifier
id currentProject = /* current project */;
id projectDoc = [currentProject performSelector:@selector(projectDocument)];
NSString *currentDocID = [projectDoc performSelector:@selector(uniqueIdentifier)];

// Decode your stored plist, update the documentID, re-encode
NSMutableDictionary *plist = [NSPropertyListSerialization
    propertyListWithData:storedPlistData
    options:NSPropertyListMutableContainers
    format:NULL error:NULL];
plist[@"ffpasteboarddocumentID"] = currentDocID;

NSData *updatedData = [NSPropertyListSerialization
    dataFromPropertyList:plist
    format:NSPropertyListBinaryFormat_v1_0
    errorDescription:NULL];
```

### Step 3: Write Updated Data and Paste

```objc
NSPasteboard *pb = [NSPasteboard generalPasteboard];
[pb clearContents];

NSString *pasteboardUTI = @"com.apple.flexo.proFFPasteboardUTI";
[pb setData:updatedData forType:pasteboardUTI];

// Paste
[timelineModule performSelector:@selector(paste:) withObject:nil];
```

### Advantages

- Preserves the exact native clipboard data with all attributes
- Works for complex effect stacks that FCPXML can't fully express

### Limitations

- Two-step process — import may briefly flash media in the browser
- `documentID` patching is fragile; the internal `ffpasteboardobject` data (FFCoder-encoded) may also contain embedded references that need the correct library context
- The `ffpasteboardobject` is opaque FFCoder data — you can't easily modify individual attributes within it

---

## Solution 3: File URL + Programmatic Attribute Restore (Simplest Fallback)

The most pragmatic approach if you just need volume and a few properties.

### Step 1: Paste via File URL

```objc
// Write the file URL to the pasteboard
NSPasteboard *pb = [NSPasteboard generalPasteboard];
[pb clearContents];
[pb writeObjects:@[[NSURL fileURLWithPath:sfxFilePath]]];

// Paste — FCP imports and places the clip with default attributes
[timelineModule performSelector:@selector(paste:) withObject:nil];
```

### Step 2: Select and Restore Attributes

After paste, the clip is on the timeline with default properties. Restore saved attributes:

```python
# Via FCPBridge JSON-RPC:

# Select the just-pasted clip
timeline_action("selectClipAtPlayhead")

# Restore volume
set_inspector_property("volume", -6.0)

# Restore other properties
set_inspector_property("opacity", 0.75)
set_inspector_property("positionX", 100.0)
set_inspector_property("positionY", 50.0)

# Restore effects (if you saved effect IDs)
# Apply via menu or effect browser
execute_menu_command(["Edit", "Paste Effects"])
```

### Advantages

- Simple, well-understood, no pasteboard hacking
- Works reliably — URL paste always succeeds
- Each attribute restoration is individually verifiable

### Limitations

- Multi-step — possible timing issues between paste and attribute application
- Can't easily restore complex effect stacks with custom parameters
- Relies on inspector property access for each attribute

---

## Solution 4: Intercept with `mediaByReferenceOnly:NO` (Advanced)

The `newEditsWithProject:mediaByReferenceOnly:options:` method on `FFPasteboard` has a boolean flag that controls media resolution behavior.

When `mediaByReferenceOnly` is YES, it sets `assetFlags` bit 14 (0x4000), meaning "only create references, expect media already linked." When NO (assetFlags = 0), and the pasteboard contains file URLs, FCP enters a different code path that uses `FFFileImporter` to actually import the media files.

### How It Works

```objc
Class FFPasteboardClass = objc_getClass("FFPasteboard");
id ffpb = [[FFPasteboardClass alloc]
    performSelector:@selector(initWithPasteboard:)
         withObject:[NSPasteboard generalPasteboard]];

id project = /* current project */;

// Call with mediaByReferenceOnly:NO to trigger media import
id edits = [ffpb performSelector:@selector(newEditsWithProject:mediaByReferenceOnly:options:)
                      withObject:project
                      withObject:@NO     // force media import
                      withObject:nil];
```

### When This Works

This path activates when the pasteboard has **file URLs** alongside other data. It:

1. Validates URLs via `FFFileImporter.validateURLs:withURLsInfo:forImportToLocation:...`
2. Imports via `FFFileImporter.importToEvent:manageFileType:processNow:...`
3. Returns imported clips as `FigTimeRangeAndObject` items

### Limitations

- Only helps when file URLs are on the pasteboard — won't rescue pure native clipboard data with missing media
- The returned objects still need to be inserted into the timeline
- More complex to orchestrate than the FCPXML approach

---

## Comparison Matrix

| Approach | Media Import | Attributes Preserved | Complexity | Reliability |
|----------|-------------|---------------------|------------|-------------|
| **1. FCPXML Pasteboard** | Automatic | All FCPXML-expressible | Medium | High |
| **2. Import + Native Paste** | Manual first step | All (native format) | High | Medium (fragile IDs) |
| **3. URL + Attribute Restore** | Automatic | Manual per-property | Low | High |
| **4. mediaByReferenceOnly** | URL-dependent | Depends on source | High | Medium |

---

## Appendix A: FCPXML Attribute Reference

Common attributes you can embed in FCPXML for Solution 1:

```xml
<!-- Audio volume -->
<adjust-volume amount="-6dB"/>

<!-- Stereo pan -->
<adjust-panner mode="stereo" amount="-25"/>

<!-- Transform (position, scale, rotation) -->
<adjust-transform position="0 0" anchor="0 0" scale="1 1" rotation="0"/>

<!-- Opacity and blend mode -->
<adjust-blend amount="1.0" mode="normal"/>

<!-- Color correction -->
<adjust-colorConform enabled="1"/>

<!-- Speed/retime -->
<timeMap>
    <timept time="0s" value="0s" interp="smooth2"/>
    <timept time="5s" value="10s" interp="smooth2"/>
</timeMap>

<!-- Markers -->
<marker start="3s" duration="1/24s" value="Important moment"/>
<chapter-marker start="5s" duration="1/24s" value="Chapter 1"/>

<!-- Keywords -->
<keyword start="0s" duration="10s" value="SFX, Foley"/>

<!-- Audio role assignment -->
<audio-role-source role="dialogue.dialogue-1"/>

<!-- Fade in/out handles -->
<adjust-volume>
    <param name="amount">
        <fadeIn type="easeIn" duration="1s"/>
        <fadeOut type="easeOut" duration="1s"/>
    </param>
</adjust-volume>
```

---

## Appendix B: Pasteboard Type Discovery Script

Run this once to capture the exact UTI strings for your FCP version:

```objc
// Call from within FCP's process (e.g., via injected dylib or FCPBridge)

Class IXType = objc_getClass("IXXMLPasteboardType");

NSLog(@"=== IXXMLPasteboardType UTIs ===");
NSLog(@"current:          %@", [IXType current]);
NSLog(@"previous:         %@", [IXType previous]);
NSLog(@"previousPrevious: %@", [IXType previousPrevious]);
NSLog(@"generic:          %@", [IXType generic]);
NSLog(@"string:           %@", [IXType string]);
NSLog(@"fileURL:          %@", [IXType fileURL]);
NSLog(@"bookmarkData:     %@", [IXType bookmarkData]);
NSLog(@"allData:          %@", [IXType allData]);
NSLog(@"all:              %@", [IXType all]);

// Also capture the native pasteboard UTI
// Look for it in registered drag types on the timeline view
id timelineModule = /* active timeline module */;
id timelineView = [timelineModule performSelector:@selector(view)];
NSLog(@"Registered types: %@", [timelineView registeredDraggedTypes]);
```

The `FFXMLTranslationTask` checks pasteboard types in this priority order:
1. `IXXMLPasteboardType.current`
2. `IXXMLPasteboardType.previous`
3. `IXXMLPasteboardType.previousPrevious`
4. `IXXMLPasteboardType.generic`
5. Falls back to `IXXMLPasteboardType.string` (reads as plain text, converts to data)

When writing FCPXML to the pasteboard, use `current` for best compatibility with the running FCP version.

---

## Appendix C: Key Internal Classes

| Class | Methods | Role |
|-------|---------|------|
| `FFPasteboard` | 76 | Clipboard read/write coordinator |
| `FFPasteboardItem` | ~20 | Serialized clipboard item (NSPasteboardWriting/Reading) |
| `FFPasteboardItemPromise` | ~15 | Lazy-loaded clipboard data (NSPasteboardItemDataProvider) |
| `FFXMLTranslationTask` | ~10 | Converts FCPXML pasteboard data for import |
| `FFXMLImportOptions` | ~15 | Configuration for XML import (incremental, conflict resolution) |
| `FFFileImporter` | ~20 | File-based media import |
| `IXXMLPasteboardType` | 18 | FCPXML pasteboard UTI type definitions |
| `FFCoder` | ~10 | Encodes/decodes FCP model objects to NSData |

---

## Appendix D: Debugging Pasteboard Contents

To inspect what's currently on the pasteboard:

```objc
NSPasteboard *pb = [NSPasteboard generalPasteboard];
NSLog(@"Types on pasteboard: %@", [pb types]);

for (NSString *type in [pb types]) {
    NSData *data = [pb dataForType:type];
    NSLog(@"Type: %@ — %lu bytes", type, (unsigned long)data.length);
    
    // Try to decode as plist (works for FFPasteboardItem data)
    id plist = [NSPropertyListSerialization
        propertyListWithData:data
        options:0 format:NULL error:NULL];
    if (plist) {
        NSLog(@"  Plist: %@", plist);
    }
    
    // Try to decode as string (works for FCPXML string type)
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (str && str.length < 2000) {
        NSLog(@"  String: %@", str);
    }
}
```

This is especially useful for capturing what FCP writes to the pasteboard when you copy a clip — you can see the exact structure of `ffpasteboardobject`, `ffpasteboardcopiedtypes`, `ffpasteboarddocumentID`, etc.
