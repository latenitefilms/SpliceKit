//
//  FCPBridge.m
//  Main entry point - constructor, class caching, app launch hook
//

#import "FCPBridge.h"
#import <AppKit/AppKit.h>

#pragma mark - Logging

static NSString *sLogPath = nil;
static NSFileHandle *sLogHandle = nil;
static dispatch_queue_t sLogQueue = nil;

static void FCPBridge_initLogging(void) {
    sLogQueue = dispatch_queue_create("com.fcpbridge.log", DISPATCH_QUEUE_SERIAL);

    // Write to ~/Desktop/fcpbridge.log (outside sandbox via absolute path exception)
    sLogPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop/fcpbridge.log"];

    // Create or truncate the log file
    [[NSFileManager defaultManager] createFileAtPath:sLogPath contents:nil attributes:nil];
    sLogHandle = [NSFileHandle fileHandleForWritingAtPath:sLogPath];
    [sLogHandle seekToEndOfFile];
}

void FCPBridge_log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // Also NSLog
    NSLog(@"[FCPBridge] %@", message);

    // Write to file
    if (sLogHandle && sLogQueue) {
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                            dateStyle:NSDateFormatterNoStyle
                                                            timeStyle:NSDateFormatterMediumStyle];
        NSString *line = [NSString stringWithFormat:@"[%@] [FCPBridge] %@\n", timestamp, message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        dispatch_async(sLogQueue, ^{
            [sLogHandle writeData:data];
            [sLogHandle synchronizeFile];
        });
    }
}

#pragma mark - Socket Path

static char sSocketPath[1024] = {0};

const char *FCPBridge_getSocketPath(void) {
    if (sSocketPath[0] != '\0') return sSocketPath;

    // Try /tmp first - works if not sandboxed or has exception
    // The entitlements include absolute-path.read-write: ["/"]
    // so /tmp should work. But if not, fall back to container.
    NSString *path = @"/tmp/fcpbridge.sock";

    // Test writability
    NSString *testPath = @"/tmp/fcpbridge_test";
    BOOL canWrite = [[NSFileManager defaultManager] createFileAtPath:testPath
                                                            contents:[@"test" dataUsingEncoding:NSUTF8StringEncoding]
                                                          attributes:nil];
    if (canWrite) {
        [[NSFileManager defaultManager] removeItemAtPath:testPath error:nil];
    } else {
        // Fall back to app container
        NSString *containerPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop/fcpbridge.sock"];
        path = containerPath;
        FCPBridge_log(@"Using fallback socket path: %@", path);
    }

    strncpy(sSocketPath, [path UTF8String], sizeof(sSocketPath) - 1);
    return sSocketPath;
}

#pragma mark - Cached Class References

Class FCPBridge_FFAnchoredTimelineModule = nil;
Class FCPBridge_FFAnchoredSequence = nil;
Class FCPBridge_FFLibrary = nil;
Class FCPBridge_FFLibraryDocument = nil;
Class FCPBridge_FFEditActionMgr = nil;
Class FCPBridge_FFModelDocument = nil;
Class FCPBridge_FFPlayer = nil;
Class FCPBridge_FFActionContext = nil;
Class FCPBridge_PEAppController = nil;
Class FCPBridge_PEDocument = nil;

#pragma mark - Compatibility Check

static void FCPBridge_checkCompatibility(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"];
    NSString *build = info[@"CFBundleVersion"];
    FCPBridge_log(@"FCP version %@ (build %@)", version, build);

    // Verify critical classes
    struct { const char *name; Class *ref; } classes[] = {
        {"FFAnchoredTimelineModule", &FCPBridge_FFAnchoredTimelineModule},
        {"FFAnchoredSequence",       &FCPBridge_FFAnchoredSequence},
        {"FFLibrary",                &FCPBridge_FFLibrary},
        {"FFLibraryDocument",        &FCPBridge_FFLibraryDocument},
        {"FFEditActionMgr",          &FCPBridge_FFEditActionMgr},
        {"FFModelDocument",          &FCPBridge_FFModelDocument},
        {"FFPlayer",                 &FCPBridge_FFPlayer},
        {"FFActionContext",          &FCPBridge_FFActionContext},
        {"PEAppController",         &FCPBridge_PEAppController},
        {"PEDocument",              &FCPBridge_PEDocument},
    };

    int found = 0, total = sizeof(classes) / sizeof(classes[0]);
    for (int i = 0; i < total; i++) {
        *classes[i].ref = objc_getClass(classes[i].name);
        if (*classes[i].ref) {
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(*classes[i].ref, &methodCount);
            free(methods);
            FCPBridge_log(@"  OK: %s (%u methods)", classes[i].name, methodCount);
            found++;
        } else {
            FCPBridge_log(@"  MISSING: %s", classes[i].name);
        }
    }
    FCPBridge_log(@"Class check: %d/%d found", found, total);
}

#pragma mark - App Launch Handler

static void FCPBridge_appDidLaunch(void) {
    FCPBridge_log(@"================================================");
    FCPBridge_log(@"App launched. Starting control server...");
    FCPBridge_log(@"================================================");

    // Run compatibility check now that all frameworks are loaded
    FCPBridge_checkCompatibility();

    // Count total loaded classes
    unsigned int classCount = 0;
    Class *allClasses = objc_copyClassList(&classCount);
    free(allClasses);
    FCPBridge_log(@"Total ObjC classes in process: %u", classCount);

    // Start the control server on a background thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        FCPBridge_startControlServer();
    });
}

#pragma mark - CloudContent Crash Prevention

static void noopMethod(id self, SEL _cmd) {
    FCPBridge_log(@"BLOCKED: -[%@ %@]", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
}

static void noopMethodWithArg(id self, SEL _cmd, id arg) {
    FCPBridge_log(@"BLOCKED: -[%@ %@]", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
}

static BOOL returnNO(id self, SEL _cmd) {
    FCPBridge_log(@"BLOCKED (returning NO): +[%@ %@]",
                  NSStringFromClass(object_getClass(self)), NSStringFromSelector(_cmd));
    return NO;
}

static void FCPBridge_disableCloudContent(void) {
    FCPBridge_log(@"Disabling CloudContent/ImagePlayground...");

    // The crash path in -[PEAppController presentMainWindowOnAppLaunch:]:
    //   if (+[CloudContentFeatureFlag isEnabled]) {  <-- gate the whole flow
    //     CloudContentCatalog.shared -> CCFirstLaunchHelper -> CloudKit (crash)
    //   }
    // Fix: make +[CloudContentFeatureFlag isEnabled] return NO

    // CloudContentFeatureFlag is a Swift class with mangled name
    // _TtC13Final_Cut_Pro23CloudContentFeatureFlag
    Class ccFlag = objc_getClass("_TtC13Final_Cut_Pro23CloudContentFeatureFlag");
    if (!ccFlag) {
        // Try alternate name
        ccFlag = objc_getClass("Final_Cut_Pro.CloudContentFeatureFlag");
    }

    if (ccFlag) {
        // Swizzle the class method +isEnabled to return NO
        Method m = class_getClassMethod(ccFlag, @selector(isEnabled));
        if (m) {
            method_setImplementation(m, (IMP)returnNO);
            FCPBridge_log(@"  Swizzled +[CloudContentFeatureFlag isEnabled] -> NO");
        } else {
            FCPBridge_log(@"  WARNING: +isEnabled not found on CloudContentFeatureFlag");
        }
    } else {
        FCPBridge_log(@"  WARNING: CloudContentFeatureFlag class not found");
    }

    // Also disable FFImagePlayground.isAvailable which can also crash
    Class ipClass = objc_getClass("_TtC5Flexo17FFImagePlayground");
    if (!ipClass) ipClass = objc_getClass("Flexo.FFImagePlayground");
    if (ipClass) {
        Method m = class_getClassMethod(ipClass, @selector(isAvailable));
        if (m) {
            method_setImplementation(m, (IMP)returnNO);
            FCPBridge_log(@"  Swizzled +[FFImagePlayground isAvailable] -> NO");
        }
    }

    FCPBridge_log(@"CloudContent/ImagePlayground disabled.");
}

#pragma mark - Constructor (called on dylib load)

__attribute__((constructor))
static void FCPBridge_init(void) {
    // Initialize logging first
    FCPBridge_initLogging();

    FCPBridge_log(@"================================================");
    FCPBridge_log(@"FCPBridge v%s initializing...", FCPBRIDGE_VERSION);
    FCPBridge_log(@"PID: %d", getpid());
    FCPBridge_log(@"Home: %@", NSHomeDirectory());
    FCPBridge_log(@"================================================");

    // Swizzle out CloudContent first-launch flow that crashes without iCloud entitlements
    FCPBridge_disableCloudContent();

    // Register for app launch notification
    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSApplicationDidFinishLaunchingNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            FCPBridge_appDidLaunch();
        }];

    FCPBridge_log(@"Constructor complete. Waiting for app launch...");
}
