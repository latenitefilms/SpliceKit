//
//  SpliceKitMediaExtensionGuard.m
//  Two policies on -[FFMediaExtensionManager copyDecoderInfo:]:
//
//    1. For codecs SpliceKit handles in-process (BRAW variants), short-circuit
//       to nil so FCP's Media Extension lookup misses and decoder selection
//       falls through to our VTRegisterVideoDecoder registration. This makes
//       SpliceKit authoritative for BRAW even when third-party extensions
//       (e.g. BRAW Toolbox) are installed and would otherwise be picked first.
//
//    2. For all other codecs, call the original but wrap in @try/@catch so
//       the NSInvalidArgumentException that VTCopyVideoDecoderExtensionProperties
//       raises when an extension returns nil for a required property key
//       doesn't take down FCP. Only that one specific exception is swallowed;
//       anything else re-raises so we don't mask unrelated bugs.
//
//  Background: the crash this started from
//  ---------------------------------------
//  2026-04-21 14:31:13 — EXC_CRASH (SIGABRT) on com.apple.flexo.thumbnailMgr.flatten:
//
//    *** -[__NSDictionaryM __setObject:forKey:]: object cannot be nil
//        (key: <one of the kVTExtensionProperties_* constants>)
//
//      VTCopyVideoDecoderExtensionProperties + 556        (VideoToolbox)
//      -[FFMediaExtensionManager copyDecoderInfo:] + 252  (Flexo)
//      -[FFMediaExtensionManager copyCodecName:] + 16     (Flexo)
//      copyVideoCodecName + 616                           (Flexo)
//      FFAVFQTMediaReader::initFromReadableAVAsset()      (Flexo)
//      ... FFMCSwitcherVideoSource newSubRangeMD5InfoForSampleDuration:atTime:context:
//      FFThumbnailRequestManager _backgroundTask:onTask:  (Flexo)
//
//  VTCopyVideoDecoderExtensionProperties (macOS 15+ public API) builds a
//  CFDictionary containing six required CFStringRef/CFURLRef values:
//      kVTExtensionProperties_ExtensionIdentifierKey
//      kVTExtensionProperties_ExtensionNameKey
//      kVTExtensionProperties_ContainingBundleNameKey
//      kVTExtensionProperties_ExtensionURLKey
//      kVTExtensionProperties_ContainingBundleURLKey
//      kVTExtensionProperties_CodecNameKey
//  If any value resolves to nil — for example, an extension whose CodecInfo
//  array does not declare an entry for the FourCC the format description
//  carries — VT calls __setObject:forKey: with nil and __NSDictionaryM raises
//  NSInvalidArgumentException, which unwinds to FCP's uncaught handler and
//  abort()s the process. We saw this on a multicam clip with BRAW angles
//  where SpliceKit registers brxq/brst/brvn/brs2/brxh variants but BRAW
//  Toolbox's installed Decoder.appex only advertises 'braw' in its CodecInfo.
//
//  Why short-circuit BRAW entirely (policy 1) instead of just catching the
//  exception
//  ---------
//  The crash is the visible symptom; the deeper issue is that BRAW Toolbox's
//  Media Extension is being picked over SpliceKit's in-process decoder, even
//  for the variants BRAW Toolbox doesn't advertise. Catching the exception
//  fixes the crash but leaves FCP routing BRAW playback through whichever
//  decoder won the lookup race — usually the third-party extension, since
//  Apple prioritises Media Extensions over legacy in-process registrations.
//  Returning nil for the BRAW FourCCs in copyDecoderInfo: makes FCP see "no
//  Media Extension for this codec", so it falls back to VT's in-process
//  registry where SpliceKitBRAW_registerInProcessDecoder has bound all six
//  variants to SpliceKitBRAWInProcess_CreateInstance.
//
//  Argument signature
//  ------------------
//  copyDecoderInfo: takes a FourCharCode (uint32 codec FourCC like 'braw' =
//  0x62726177), NOT an Objective-C object. Declaring the parameter as `id`
//  would make ARC emit objc_storeStrong on entry, which segfaults trying to
//  dereference the FourCC value as an object pointer. We saw this on the
//  very first deploy of this guard (2026-04-21 15:03:54): EXC_BAD_ACCESS at
//  0x62726177 inside MEG_swizzledCopyDecoderInfo+68 → objc_storeStrong+60.
//  Using uintptr_t for the parameter passes the register value through with
//  no ARC retain. The 32-bit FourCharCode lives in the low half of the
//  64-bit arg register on ARM64; the original method reads it back as a
//  uint32 and never notices the wider-than-needed type.

#import "SpliceKit.h"
#import <objc/runtime.h>
#import <objc/message.h>

static IMP sOrigCopyDecoderInfo = NULL;
static IMP sOrigCopyProcessorInfo = NULL;
static IMP sOrigIsAppExclusiveDecoder = NULL;
static IMP sOrigIsDecoderUsingMediaExtension = NULL;
static BOOL sMediaExtensionGuardInstalled = NO;

// Codecs SpliceKit handles in-process via VTRegisterVideoDecoder
// (SpliceKitBRAWDecoderInProcess.mm registers all six variants on startup).
// When FFMediaExtensionManager is asked for one of these we return nil so
// FCP's decoder selection falls past the Media Extension layer and lands on
// our in-process registration. Synced with the FourCC list in
// SpliceKitBRAWDecoderInProcess.mm:524 and the format-description filter in
// SpliceKitBRAW.mm:1743.
static BOOL MEG_isSpliceKitOwnedCodec(uint32_t fourcc) {
    switch (fourcc) {
    case 'braw': case 'brxq': case 'brst':
    case 'brvn': case 'brs2': case 'brxh':
        return YES;
    default:
        return NO;
    }
}

static NSString *MEG_fourCCString(uint32_t fourcc) {
    char chars[5] = {
        (char)((fourcc >> 24) & 0xFF),
        (char)((fourcc >> 16) & 0xFF),
        (char)((fourcc >> 8)  & 0xFF),
        (char)(fourcc         & 0xFF),
        0,
    };
    return [NSString stringWithUTF8String:chars];
}

// Per-FourCC log-once for the routing decision so a thumbnail flood doesn't
// spam the log; we still want to see which codecs we've redirected at least
// once per launch.
static void MEG_logRoutingDecisionOnce(uint32_t fourcc) {
    static NSMutableSet<NSNumber *> *seen = nil;
    static dispatch_once_t once;
    static dispatch_queue_t q;
    dispatch_once(&once, ^{
        seen = [NSMutableSet set];
        q = dispatch_queue_create("com.splicekit.mediaextensionguard.routing", DISPATCH_QUEUE_SERIAL);
    });
    NSNumber *key = @(fourcc);
    dispatch_async(q, ^{
        if ([seen containsObject:key]) return;
        [seen addObject:key];
        SpliceKit_log(@"[MediaExtensionGuard] routing %@ (0x%08x) past Media Extension lookup → in-process VT decoder",
                      MEG_fourCCString(fourcc), fourcc);
    });
}

static void MEG_logCatch(NSException *exception, uint32_t fourcc) {
    static NSUInteger sCatchCount = 0;
    static NSDate *sLastLog = nil;
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.splicekit.mediaextensionguard.log", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(q, ^{
        sCatchCount++;
        // First catch logs in full; thereafter, throttle to once per minute and
        // include the running count so the user knows it's still happening.
        NSDate *now = [NSDate date];
        if (sLastLog && [now timeIntervalSinceDate:sLastLog] < 60.0) return;
        sLastLog = now;
        SpliceKit_log(@"[MediaExtensionGuard] swallowed %@ from copyDecoderInfo: "
                       "for %@ (0x%08x) (count=%lu) reason=%@",
                       exception.name, MEG_fourCCString(fourcc), fourcc,
                       (unsigned long)sCatchCount,
                       exception.reason ?: @"(no reason)");
    });
}

// The exception we want to swallow has a very specific signature: it's an
// NSInvalidArgumentException raised by NSMutableDictionary when its setter is
// called with nil. Anything else is re-raised so we don't mask unrelated bugs
// (a real ObjC selector mismatch in copyDecoderInfo:, for example).
static BOOL MEG_isVTNilPropertyException(NSException *exception) {
    if (![exception.name isEqualToString:NSInvalidArgumentException]) return NO;
    NSString *reason = exception.reason ?: @"";
    return [reason containsString:@"__setObject:forKey:"]
        && [reason containsString:@"object cannot be nil"];
}

static id MEG_swizzledCopyDecoderInfo(id self, SEL _cmd, uintptr_t arg) {
    if (!sOrigCopyDecoderInfo) return nil;

    // FCP packs the codec FourCC into the low 32 bits of the third argument
    // register; truncate to read it back without dereferencing.
    uint32_t fourcc = (uint32_t)arg;

    if (MEG_isSpliceKitOwnedCodec(fourcc)) {
        MEG_logRoutingDecisionOnce(fourcc);
        return nil;
    }

    @try {
        return ((id (*)(id, SEL, uintptr_t))sOrigCopyDecoderInfo)(self, _cmd, arg);
    } @catch (NSException *exception) {
        if (MEG_isVTNilPropertyException(exception)) {
            MEG_logCatch(exception, fourcc);
            // Returning nil mirrors the kVTCouldNotFindExtensionErr path, which
            // copyCodecName: handles by falling back to the built-in codec
            // table. The thumbnail render proceeds without the extension's
            // codec name annotation.
            return nil;
        }
        @throw;
    }
}

// copyProcessorInfo: shares its signature with copyDecoderInfo: (returns
// FFMediaExtensionInfo for the matched RAW processor extension). Same
// FourCC arg, same nil-property crash potential, same routing intent —
// SpliceKit handles BRAW RAW adjustments in-process via the
// FFSourceVideoFig.setRAWAdjustmentInfo: hook in SpliceKitBRAWRAW.mm, and
// we don't want a third-party RAW processor (Apple ProRes RAW Processor,
// BRAW Toolbox RAW Processor, nablet) inserted into the pipeline for BRAW
// FourCCs.
static id MEG_swizzledCopyProcessorInfo(id self, SEL _cmd, uintptr_t arg) {
    if (!sOrigCopyProcessorInfo) return nil;
    uint32_t fourcc = (uint32_t)arg;

    if (MEG_isSpliceKitOwnedCodec(fourcc)) {
        MEG_logRoutingDecisionOnce(fourcc);
        return nil;
    }

    @try {
        return ((id (*)(id, SEL, uintptr_t))sOrigCopyProcessorInfo)(self, _cmd, arg);
    } @catch (NSException *exception) {
        if (MEG_isVTNilPropertyException(exception)) {
            MEG_logCatch(exception, fourcc);
            return nil;
        }
        @throw;
    }
}

// isAppExclusiveDecoder: returns YES when FCP should treat the in-app
// decoder as authoritative (skipping Media Extension lookup) for the given
// FourCC. BRAW decoders SpliceKit owns get a hard YES here; everything
// else passes through to FCP's normal logic.
static BOOL MEG_swizzledIsAppExclusiveDecoder(id self, SEL _cmd, uintptr_t arg) {
    uint32_t fourcc = (uint32_t)arg;
    if (MEG_isSpliceKitOwnedCodec(fourcc)) return YES;
    if (!sOrigIsAppExclusiveDecoder) return NO;
    return ((BOOL (*)(id, SEL, uintptr_t))sOrigIsAppExclusiveDecoder)(self, _cmd, arg);
}

// isDecoderUsingMediaExtension: returns YES when FCP routes the codec
// through a Media Extension. We override to NO for BRAW so any callers
// that gate on this predicate (cache invalidation, Inspector display,
// asset-rep-provider selection in -[FFAsset _newMediaRepProviderForQuality:])
// believe FCP is using the in-process path even if a third-party Media
// Extension is registered for the codec.
static BOOL MEG_swizzledIsDecoderUsingMediaExtension(id self, SEL _cmd, uintptr_t arg) {
    uint32_t fourcc = (uint32_t)arg;
    if (MEG_isSpliceKitOwnedCodec(fourcc)) return NO;
    if (!sOrigIsDecoderUsingMediaExtension) return NO;
    return ((BOOL (*)(id, SEL, uintptr_t))sOrigIsDecoderUsingMediaExtension)(self, _cmd, arg);
}

// Dump every instance + class method on a class so we can see what other
// hooks might exist for format reader / RAW processor selection. Logged once
// at install time. Output goes to ~/Library/Logs/SpliceKit/splicekit.log.
static void MEG_dumpClassMethods(Class cls, const char *label) {
    if (!cls) return;
    NSMutableArray *names = [NSMutableArray array];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        [names addObject:[@"-" stringByAppendingString:NSStringFromSelector(method_getName(methods[i]))]];
    }
    free(methods);
    Class meta = object_getClass((id)cls);
    methods = class_copyMethodList(meta, &count);
    for (unsigned int i = 0; i < count; i++) {
        [names addObject:[@"+" stringByAppendingString:NSStringFromSelector(method_getName(methods[i]))]];
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    SpliceKit_log(@"[MediaExtensionGuard] %s methods (%lu): %@",
                  label, (unsigned long)names.count,
                  [names componentsJoinedByString:@" | "]);
}

void SpliceKit_installMediaExtensionGuard(void) {
    if (sMediaExtensionGuardInstalled) return;

    Class cls = objc_getClass("FFMediaExtensionManager");
    if (!cls) {
        SpliceKit_log(@"[MediaExtensionGuard] FFMediaExtensionManager class not found; skipping");
        return;
    }

    // One-shot API surface dump so we can see what other format-reader /
    // raw-processor selection hooks live on these classes — the third-party
    // BRAW Toolbox Format Reader is still winning the lookup race even with
    // the decoder swizzle in place, and we need to know which method to
    // intercept next. Also dump FFProviderFig because the asset-side
    // copyMediaExtensionInfo call appears in the crash trace.
    MEG_dumpClassMethods(cls, "FFMediaExtensionManager");
    MEG_dumpClassMethods(objc_getClass("FFProviderFig"), "FFProviderFig");

    // copyDecoderInfo: is the load-bearing swizzle — both crash-guard and
    // routing depend on it. If it doesn't exist, abort early; the other
    // hooks below are best-effort and individual failures are logged but
    // don't block install.
    SEL sel = @selector(copyDecoderInfo:);
    if (![cls instancesRespondToSelector:sel]) {
        SpliceKit_log(@"[MediaExtensionGuard] -[FFMediaExtensionManager copyDecoderInfo:] missing; skipping");
        return;
    }

    sOrigCopyDecoderInfo = SpliceKit_swizzleMethod(cls, sel, (IMP)MEG_swizzledCopyDecoderInfo);
    if (!sOrigCopyDecoderInfo) {
        SpliceKit_log(@"[MediaExtensionGuard] swizzle failed; FCP remains exposed to the VT nil-property crash and BRAW will route through third-party extensions");
        return;
    }

    // Best-effort hooks for the other Media-Extension routing predicates.
    // Each is independent — missing or swizzle-failed selectors degrade
    // gracefully (we just don't override that predicate for BRAW).
    if ([cls instancesRespondToSelector:@selector(copyProcessorInfo:)]) {
        sOrigCopyProcessorInfo = SpliceKit_swizzleMethod(
            cls, @selector(copyProcessorInfo:), (IMP)MEG_swizzledCopyProcessorInfo);
    }
    if ([cls instancesRespondToSelector:@selector(isAppExclusiveDecoder:)]) {
        sOrigIsAppExclusiveDecoder = SpliceKit_swizzleMethod(
            cls, @selector(isAppExclusiveDecoder:), (IMP)MEG_swizzledIsAppExclusiveDecoder);
    }
    if ([cls instancesRespondToSelector:@selector(isDecoderUsingMediaExtension:)]) {
        sOrigIsDecoderUsingMediaExtension = SpliceKit_swizzleMethod(
            cls, @selector(isDecoderUsingMediaExtension:), (IMP)MEG_swizzledIsDecoderUsingMediaExtension);
    }

    sMediaExtensionGuardInstalled = YES;
    SpliceKit_log(@"[MediaExtensionGuard] installed: BRAW codecs (braw/brxq/brst/brvn/brs2/brxh) "
                  @"redirected past Media Extension routing — copyDecoderInfo:%s "
                  @"copyProcessorInfo:%s isAppExclusiveDecoder:%s isDecoderUsingMediaExtension:%s",
                  sOrigCopyDecoderInfo ? "✓" : "✗",
                  sOrigCopyProcessorInfo ? "✓" : "✗",
                  sOrigIsAppExclusiveDecoder ? "✓" : "✗",
                  sOrigIsDecoderUsingMediaExtension ? "✓" : "✗");
}
