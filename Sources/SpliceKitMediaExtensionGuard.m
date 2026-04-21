//
//  SpliceKitMediaExtensionGuard.m
//  Catch the NSInvalidArgumentException that VTCopyVideoDecoderExtensionProperties
//  raises when an installed Media Extension returns nil for one of the keys VT
//  unconditionally setObject:forKey:s into its properties dictionary.
//
//  The crash
//  ---------
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
//      ...
//      FFMCSwitcherVideoSource newSubRangeMD5InfoForSampleDuration:atTime:context:
//      FFThumbnailRequestManager _backgroundTask:onTask:  (Flexo)
//
//  Why it happens
//  --------------
//  VTCopyVideoDecoderExtensionProperties (macOS 15+ public API) builds a
//  CFDictionary containing six required CFStringRef/CFURLRef values:
//      kVTExtensionProperties_ExtensionIdentifierKey
//      kVTExtensionProperties_ExtensionNameKey
//      kVTExtensionProperties_ContainingBundleNameKey
//      kVTExtensionProperties_ExtensionURLKey
//      kVTExtensionProperties_ContainingBundleURLKey
//      kVTExtensionProperties_CodecNameKey
//  If any installed Media Extension's metadata fails to resolve one of these
//  (for example, an extension's CodecInfo plist array does not contain an
//  entry for the FourCC the format description carries — common when SpliceKit
//  registers BRAW variants like brxq/brst/brvn/brs2/brxh that third-party
//  decoders only declare 'braw' for) VT calls __setObject:forKey: with nil and
//  __NSDictionaryM throws NSInvalidArgumentException. The exception unwinds
//  through Flexo's copyDecoderInfo: into the thumbnail dispatch block, hits
//  FCP's uncaught-exception handler, and abort()s the process.
//
//  The fix
//  -------
//  Wrap -[FFMediaExtensionManager copyDecoderInfo:] with a @try/@catch that
//  swallows ONLY this specific NSInvalidArgumentException (matched on the
//  __setObject:forKey: + "object cannot be nil" reason text). Any other
//  exception is re-raised so we don't mask unrelated bugs. On catch we return
//  nil, which propagates up to copyVideoCodecName as "no extension info
//  available" — FCP falls back to its built-in codec name resolver and the
//  thumbnail render continues without the extension annotation. This is the
//  same outcome FCP would see if the extension simply weren't installed for
//  that codec, which it handles cleanly.
//
//  Trade-off
//  ---------
//  Swallowing the exception hides the underlying nil-property bug from the
//  extension vendor (BRAW Toolbox, nablet Sony Raw, QLVideo, etc.). We log
//  every catch so users can report the malformed extension upstream, but the
//  practical alternative — letting FCP crash on every project that touches
//  one of these clips — is worse.

#import "SpliceKit.h"
#import <objc/runtime.h>
#import <objc/message.h>

static IMP sOrigCopyDecoderInfo = NULL;
static BOOL sMediaExtensionGuardInstalled = NO;

// Logging is rate-limited so a thumbnail flood doesn't fill the disk.
static dispatch_queue_t MEG_logQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.splicekit.mediaextensionguard.log", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static void MEG_logCatch(NSException *exception) {
    static NSUInteger sCatchCount = 0;
    static NSDate *sLastLog = nil;
    dispatch_async(MEG_logQueue(), ^{
        sCatchCount++;
        // First catch logs in full; thereafter, throttle to once per minute and
        // include the running count so the user knows it's still happening.
        NSDate *now = [NSDate date];
        if (sLastLog && [now timeIntervalSinceDate:sLastLog] < 60.0) return;
        sLastLog = now;
        SpliceKit_log(@"[MediaExtensionGuard] swallowed %@ from copyDecoderInfo: "
                       "(count=%lu) reason=%@",
                       exception.name, (unsigned long)sCatchCount,
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

// copyDecoderInfo: takes a FourCharCode (uint32 codec FourCC like 'braw' =
// 0x62726177), NOT an Objective-C object. Declaring the parameter as `id`
// would make ARC emit objc_storeStrong on entry, which segfaults trying to
// dereference the FourCC value as an object pointer. We saw this on the very
// first deploy of this guard (2026-04-21 15:03:54): EXC_BAD_ACCESS at
// 0x62726177 inside MEG_swizzledCopyDecoderInfo+68 → objc_storeStrong+60.
// Using `void *` for the parameter passes the register value through with no
// ARC retain. The 32-bit FourCharCode lives in the low half of the 64-bit arg
// register on ARM64; the original method reads it back as a uint32 and never
// notices the wider-than-needed type.
static id MEG_swizzledCopyDecoderInfo(id self, SEL _cmd, void *arg) {
    if (!sOrigCopyDecoderInfo) return nil;
    @try {
        return ((id (*)(id, SEL, void *))sOrigCopyDecoderInfo)(self, _cmd, arg);
    } @catch (NSException *exception) {
        if (MEG_isVTNilPropertyException(exception)) {
            MEG_logCatch(exception);
            // Returning nil mirrors the kVTCouldNotFindExtensionErr path, which
            // copyCodecName: handles by falling back to the built-in codec
            // table. The thumbnail render proceeds without the extension's
            // codec name annotation.
            return nil;
        }
        @throw;
    }
}

void SpliceKit_installMediaExtensionGuard(void) {
    if (sMediaExtensionGuardInstalled) return;

    Class cls = objc_getClass("FFMediaExtensionManager");
    if (!cls) {
        SpliceKit_log(@"[MediaExtensionGuard] FFMediaExtensionManager class not found; skipping");
        return;
    }

    SEL sel = @selector(copyDecoderInfo:);
    if (![cls instancesRespondToSelector:sel]) {
        SpliceKit_log(@"[MediaExtensionGuard] -[FFMediaExtensionManager copyDecoderInfo:] missing; skipping");
        return;
    }

    sOrigCopyDecoderInfo = SpliceKit_swizzleMethod(cls, sel, (IMP)MEG_swizzledCopyDecoderInfo);
    if (!sOrigCopyDecoderInfo) {
        SpliceKit_log(@"[MediaExtensionGuard] swizzle failed; FCP remains exposed to the VT nil-property crash");
        return;
    }

    sMediaExtensionGuardInstalled = YES;
    SpliceKit_log(@"[MediaExtensionGuard] installed: copyDecoderInfo: now catches __setObject:forKey: nil exceptions from VTCopyVideoDecoderExtensionProperties");
}
