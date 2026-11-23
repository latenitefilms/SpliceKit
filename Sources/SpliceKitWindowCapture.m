#import "SpliceKitWindowCapture.h"
#import "SpliceKit.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>

@interface SpliceKitPasteSnapshotView : NSImageView
@end

@implementation SpliceKitPasteSnapshotView
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

static BOOL SpliceKit_waitForWindowCapture(dispatch_semaphore_t done, NSTimeInterval timeout) {
    if (!NSThread.isMainThread) {
        return dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC)) == 0;
    }

    // In-process Lua callers can be on the main thread. Keep AppKit running
    // while ScreenCaptureKit delivers the asynchronous result.
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW) != 0) {
        if (NSProcessInfo.processInfo.systemUptime >= deadline) return NO;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    }
    return YES;
}

static NSBitmapImageRep *SpliceKit_windowBitmap(CGWindowID windowID, SCCaptureResolutionType resolution,
                                                NSTimeInterval timeout, NSString **failure) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSBitmapImageRep *bitmap = nil;
    __block NSString *message = nil;

    void (^capture)(SCShareableContent *, NSError *) = ^(SCShareableContent *content, NSError *error) {
        for (SCWindow *window in content.windows) {
            if (window.windowID != windowID ||
                window.owningApplication.processID != NSProcessInfo.processInfo.processIdentifier) continue;

            SCContentFilter *filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
            SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
            config.ignoreShadowsSingleWindow = YES;
            config.showsCursor = NO;
            config.captureResolution = resolution;
            CGFloat scale = resolution == SCCaptureResolutionBest ? filter.pointPixelScale : 1;
            config.width = MAX(1, lround(filter.contentRect.size.width * scale));
            config.height = MAX(1, lround(filter.contentRect.size.height * scale));
            [SCScreenshotManager captureImageWithFilter:filter configuration:config
                completionHandler:^(CGImageRef image, NSError *captureError) {
                    if (image) bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
                    message = captureError.localizedDescription;
                    dispatch_semaphore_signal(done);
                }];
            return;
        }
        message = error.localizedDescription ?: @"The FCP window is no longer available for capture";
        dispatch_semaphore_signal(done);
    };
    if (@available(macOS 14.4, *)) {
        [SCShareableContent getCurrentProcessShareableContentWithCompletionHandler:capture];
    } else {
        [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:NO completionHandler:capture];
    }

    if (!SpliceKit_waitForWindowCapture(done, timeout)) {
        if (failure) *failure = @"Timed out capturing the FCP window";
        return nil;
    }
    if (!bitmap && failure) *failure = message ?: @"ScreenCaptureKit could not capture the FCP window";
    return bitmap;
}

static CGRect SpliceKit_windowCropForView(NSView *view, CGFloat windowHeight) {
    if (!view) return CGRectNull;
    NSRect rect = [view convertRect:view.bounds toView:nil];
    return CGRectMake(NSMinX(rect), windowHeight - NSMaxY(rect), NSWidth(rect), NSHeight(rect));
}

static NSBitmapImageRep *SpliceKit_cropWindowBitmap(NSBitmapImageRep *full, CGSize windowSize, CGRect crop) {
    if (!full || windowSize.width <= 0 || windowSize.height <= 0 || CGRectIsNull(crop)) return nil;
    CGAffineTransform scale = CGAffineTransformMakeScale(full.pixelsWide / windowSize.width,
                                                         full.pixelsHigh / windowSize.height);
    CGRect pixels = CGRectIntersection(CGRectApplyAffineTransform(crop, scale),
                                       CGRectMake(0, 0, full.pixelsWide, full.pixelsHigh));
    if (CGRectIsEmpty(pixels)) return nil;
    CGImageRef cropped = CGImageCreateWithImageInRect(full.CGImage, pixels);
    if (!cropped) return nil;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cropped];
    CGImageRelease(cropped);
    return bitmap;
}

static BOOL SpliceKit_canSnapshotWithoutPrompt(void) {
    if (@available(macOS 14.4, *)) return YES; // Current-process window capture.
    return CGPreflightScreenCaptureAccess();
}

NSView *SpliceKit_showPasteSnapshot(NSView *content) {
    NSWindow *window = content.window;
    if (!window.isVisible || window.windowNumber <= 0 || NSIsEmptyRect(content.bounds)) return nil;
    if (!SpliceKit_canSnapshotWithoutPrompt()) return nil;

    NSSize windowSize = window.frame.size;
    CGRect crop = SpliceKit_windowCropForView(content, windowSize.height);
    NSBitmapImageRep *full = SpliceKit_windowBitmap((CGWindowID)window.windowNumber, SCCaptureResolutionBest, 0.5, NULL);
    if (content.window != window || !NSEqualSizes(windowSize, window.frame.size)) return nil;
    NSBitmapImageRep *bitmap = SpliceKit_cropWindowBitmap(full, windowSize, crop);
    if (!bitmap) return nil;
    bitmap.size = content.bounds.size;
    NSImage *image = [[NSImage alloc] initWithSize:bitmap.size];
    [image addRepresentation:bitmap];
    SpliceKitPasteSnapshotView *cover = [[SpliceKitPasteSnapshotView alloc] initWithFrame:content.bounds];
    cover.image = image;
    cover.imageScaling = NSImageScaleAxesIndependently;
    cover.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    cover.accessibilityHidden = YES;
    [content addSubview:cover positioned:NSWindowAbove relativeTo:nil];

    // The import pumps the main run loop while waiting for Final Cut Pro.
    __weak NSView *weakCover = cover;
    NSTimer *timeout = [NSTimer timerWithTimeInterval:8 repeats:NO block:^(NSTimer *timer) {
        [weakCover removeFromSuperview];
    }];
    [NSRunLoop.mainRunLoop addTimer:timeout forMode:NSRunLoopCommonModes];
    return cover;
}

NSDictionary *SpliceKit_captureWindowView(NSString *outputPath, SpliceKitCaptureViewSelector selectView) {
    if (![outputPath isKindOfClass:NSString.class] || !outputPath.length) return @{@"error": @"Invalid screenshot path"};

    __block CGWindowID windowID = kCGNullWindowID;
    __block CGSize windowSize = CGSizeZero;
    __block CGRect crop = CGRectNull;
    __block NSDictionary *metadata = nil;
    dispatch_semaphore_t prepared = dispatch_semaphore_create(0);
    SpliceKit_executeOnMainThread(^{
        @try {
            NSWindow *window = NSApp.mainWindow;
            if (!window) {
                for (NSWindow *candidate in NSApp.windows) {
                    if (candidate.isVisible && (!window || candidate.frame.size.width > window.frame.size.width)) {
                        window = candidate;
                    }
                }
            }
            if (!window || window.windowNumber <= 0) {
                metadata = @{@"error": @"No visible FCP window found"};
                return;
            }
            NSMutableDictionary *details = [NSMutableDictionary dictionary];
            NSView *view = selectView(window, details);
            windowSize = window.frame.size;
            crop = SpliceKit_windowCropForView(view, windowSize.height);
            windowID = (CGWindowID)window.windowNumber;
            metadata = details;
        } @catch (NSException *exception) {
            metadata = @{@"error": exception.reason ?: exception.name};
        } @finally {
            dispatch_semaphore_signal(prepared);
        }
    });
    if (dispatch_semaphore_wait(prepared, DISPATCH_TIME_NOW)) return @{@"error": @"Timed out locating the FCP window"};
    if (metadata[@"error"]) return metadata;

    NSString *failure = nil;
    NSBitmapImageRep *full = SpliceKit_windowBitmap(windowID, SCCaptureResolutionNominal, 10, &failure);
    if (!full) return @{@"error": failure};

    NSBitmapImageRep *output = SpliceKit_cropWindowBitmap(full, windowSize, crop) ?: full;
    NSData *png = [output representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png && output != full) {
        output = full;
        png = [full representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    }
    if (!png) return @{@"error": @"Failed to generate PNG data"};
    if (![png writeToFile:outputPath atomically:YES]) return @{@"error": [NSString stringWithFormat:@"Failed to write to %@", outputPath]};

    NSMutableDictionary *result = [metadata mutableCopy];
    [result addEntriesFromDictionary:@{@"status": @"ok", @"path": outputPath,
                                       @"width": @(output.pixelsWide), @"height": @(output.pixelsHigh),
                                       @"bytes": @(png.length), @"cropped": @(output != full)}];
    return result;
}
