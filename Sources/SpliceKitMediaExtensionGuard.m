//
//  SpliceKitMediaExtensionGuard.m
//  Crash guard for -[FFMediaExtensionManager copyDecoderInfo:] and
//  -[FFMediaExtensionManager copyProcessorInfo:].
//
//  Both call VTCopyVideoDecoderExtensionProperties (macOS 15+), which builds a
//  CFDictionary containing six required CFStringRef/CFURLRef values:
//      kVTExtensionProperties_ExtensionIdentifierKey
//      kVTExtensionProperties_ExtensionNameKey
//      kVTExtensionProperties_ContainingBundleNameKey
//      kVTExtensionProperties_ExtensionURLKey
//      kVTExtensionProperties_ContainingBundleURLKey
//      kVTExtensionProperties_CodecNameKey
//  If any value resolves to nil — for example, a third-party Media Extension
//  whose CodecInfo array does not declare an entry for the FourCC a format
//  description carries — VT calls __setObject:forKey: with nil and
//  __NSDictionaryM raises NSInvalidArgumentException, which unwinds to FCP's
//  uncaught handler and abort()s the process:
//
//    *** -[__NSDictionaryM __setObject:forKey:]: object cannot be nil
//
//      VTCopyVideoDecoderExtensionProperties + 556        (VideoToolbox)
//      -[FFMediaExtensionManager copyDecoderInfo:] + 252  (Flexo)
//      -[FFMediaExtensionManager copyCodecName:] + 16     (Flexo)
//      copyVideoCodecName + 616                           (Flexo)
//      FFAVFQTMediaReader::initFromReadableAVAsset()      (Flexo)
//      FFThumbnailRequestManager _backgroundTask:onTask:  (Flexo)
//
//  We call the original inside @try/@catch and swallow only that specific
//  exception, returning nil (the same result as kVTCouldNotFindExtensionErr,
//  which FCP already handles by falling back to its built-in codec table).
//  Anything else is re-raised so unrelated bugs are not masked. Decoder and
//  RAW processor selection is left entirely to FCP, so third-party Media
//  Extensions (e.g. BRAW Toolbox) are used exactly as in stock FCP.
//
//  Argument signature
//  ------------------
//  copyDecoderInfo:/copyProcessorInfo: take a FourCharCode (uint32 codec
//  FourCC like 'braw' = 0x62726177), NOT an Objective-C object. Declaring the
//  parameter as `id` would make ARC emit objc_storeStrong on entry, which
//  segfaults trying to dereference the FourCC value as an object pointer.
//  Using uintptr_t passes the register value through with no ARC retain. The
//  32-bit FourCharCode lives in the low half of the 64-bit arg register; the
//  original method reads it back as a uint32 and never notices the
//  wider-than-needed type.

#import "SpliceKit.h"
#import <objc/runtime.h>
#import <objc/message.h>

static IMP sOrigCopyDecoderInfo = NULL;
static IMP sOrigCopyProcessorInfo = NULL;
static BOOL sMediaExtensionGuardInstalled = NO;

static NSString *MEG_fourCCString(uint32_t fourcc) {
    char chars[5] = {
        (char)((fourcc >> 24) & 0xFF),
        (char)((fourcc >> 16) & 0xFF),
        (char)((fourcc >> 8)  & 0xFF),
        (char)(fourcc         & 0xFF),
        0,
    };
    NSString *s = [NSString stringWithUTF8String:chars];
    return s ?: [NSString stringWithFormat:@"0x%08x", fourcc];
}

static void MEG_logCatch(NSException *exception, uint32_t fourcc, const char *selName) {
    static NSUInteger sCatchCount = 0;
    static NSDate *sLastLog = nil;
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.splicekit.mediaextensionguard.log", DISPATCH_QUEUE_SERIAL);
    });
    NSString *name = exception.name;
    NSString *reason = exception.reason;
    dispatch_async(q, ^{
        sCatchCount++;
        // First catch logs in full; thereafter, throttle to once per minute and
        // include the running count so the user knows it's still happening.
        NSDate *now = [NSDate date];
        if (sLastLog && [now timeIntervalSinceDate:sLastLog] < 60.0) return;
        sLastLog = now;
        SpliceKit_log(@"[MediaExtensionGuard] swallowed %@ from %s "
                       "for %@ (0x%08x) (count=%lu) reason=%@",
                       name, selName, MEG_fourCCString(fourcc), fourcc,
                       (unsigned long)sCatchCount,
                       reason ?: @"(no reason)");
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
    @try {
        return ((id (*)(id, SEL, uintptr_t))sOrigCopyDecoderInfo)(self, _cmd, arg);
    } @catch (NSException *exception) {
        if (MEG_isVTNilPropertyException(exception)) {
            MEG_logCatch(exception, (uint32_t)arg, "copyDecoderInfo:");
            return nil;
        }
        @throw;
    }
}

static id MEG_swizzledCopyProcessorInfo(id self, SEL _cmd, uintptr_t arg) {
    if (!sOrigCopyProcessorInfo) return nil;
    @try {
        return ((id (*)(id, SEL, uintptr_t))sOrigCopyProcessorInfo)(self, _cmd, arg);
    } @catch (NSException *exception) {
        if (MEG_isVTNilPropertyException(exception)) {
            MEG_logCatch(exception, (uint32_t)arg, "copyProcessorInfo:");
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

    if ([cls instancesRespondToSelector:@selector(copyDecoderInfo:)]) {
        sOrigCopyDecoderInfo = SpliceKit_swizzleMethod(
            cls, @selector(copyDecoderInfo:), (IMP)MEG_swizzledCopyDecoderInfo);
    }
    if ([cls instancesRespondToSelector:@selector(copyProcessorInfo:)]) {
        sOrigCopyProcessorInfo = SpliceKit_swizzleMethod(
            cls, @selector(copyProcessorInfo:), (IMP)MEG_swizzledCopyProcessorInfo);
    }

    if (!sOrigCopyDecoderInfo && !sOrigCopyProcessorInfo) {
        SpliceKit_log(@"[MediaExtensionGuard] no hooks installed; FCP remains exposed to the "
                      @"VT nil-property crash from incomplete Media Extensions");
        return;
    }

    sMediaExtensionGuardInstalled = YES;
    SpliceKit_log(@"[MediaExtensionGuard] installed crash guard — copyDecoderInfo:%s copyProcessorInfo:%s",
                  sOrigCopyDecoderInfo ? "✓" : "✗",
                  sOrigCopyProcessorInfo ? "✓" : "✗");
}
