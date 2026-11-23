#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Select the view on the main thread. A nil view captures the whole window.
typedef NSView * _Nullable (^SpliceKitCaptureViewSelector)(NSWindow *window, NSMutableDictionary *metadata);
NSDictionary *SpliceKit_captureWindowView(NSString *outputPath, SpliceKitCaptureViewSelector selectView);

// Cover the editor while an FCPXML paste switches projects. Call on the main thread.
NSView * _Nullable SpliceKit_showPasteSnapshot(NSView * _Nullable content);

NS_ASSUME_NONNULL_END
