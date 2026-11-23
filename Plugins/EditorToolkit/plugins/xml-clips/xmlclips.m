// xml clips: after any xml import, put every clip used in the imported timeline into the library browser
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
static void XL(NSString *s) {
    FILE *f = fopen([[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/SpliceKit/xmlclips.log"] fileSystemRepresentation], "a");
    if (f) { fprintf(f, "%s %s\n", [NSDate date].description.UTF8String, s.UTF8String); fclose(f); }
}
static id XO(id o, NSString *s) {
    if (!o) return nil; SEL sel = NSSelectorFromString(s);
    if (![o respondsToSelector:sel]) return nil;
    NSMethodSignature *sig = [o methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, "@") != 0) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(o, sel);
}
static void Collect(id item, NSMutableArray *out, int depth) {
    if (!item || depth > 3) return;
    [out addObject:item];
    for (id a in (NSSet *)XO(item, @"anchoredItems")) Collect(a, out, depth + 1);
}
// What a timeline item was made from: its media assets plus, for compound and multicam clips, the clips
// it refers to. Display names don't identify a source - camera files repeat names, and clips get renamed.
static NSString *SourceKey(id it) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *s in @[@"assetsIncludingAnchored:", @"clipRefsIncludingAnchored:"]) {
        SEL sel = NSSelectorFromString(s);
        if (![it respondsToSelector:sel]) continue;
        id c = ((id(*)(id,SEL,BOOL))objc_msgSend)(it, sel, NO);   // NO: not its connected clips (they are visited themselves)
        if (![c conformsToProtocol:@protocol(NSFastEnumeration)]) continue;
        for (id x in c) [parts addObject:[NSString stringWithFormat:@"%p", x]];
    }
    if (!parts.count) return [NSString stringWithFormat:@"item:%p", it];   // unknown: let the reveal itself decide
    [parts sortUsingSelector:@selector(compare:)];
    return [parts componentsJoinedByString:@","];
}
static void AddClipsToBrowser(void) {
    @try {
        id tm = XO(XO([NSApp delegate], @"activeEditorContainer"), @"timelineModule");
        id seq = XO(tm, @"sequence");
        id prim = XO(seq, @"primaryObject");
        if (!tm || !prim) { XL(@"no timeline"); return; }
        NSMutableArray *items = [NSMutableArray array];
        for (id it in (NSArray *)XO(prim, @"containedItems")) Collect(it, items, 0);
        SEL sSet = NSSelectorFromString(@"setSelectedItems:");
        SEL sRev = NSSelectorFromString(@"_revealAncestor:addeddNewAncestorToEvent:");
        if (![tm respondsToSelector:sSet] || ![tm respondsToSelector:sRev]) { XL(@"missing selectors"); return; }
        NSArray *oldSel = XO(tm, @"selectedItems") ?: @[];
        NSMutableSet *seen = [NSMutableSet set];
        int added = 0, tried = 0;
        for (id it in items) {
            NSString *cls = NSStringFromClass([it class]);
            if (![cls containsString:@"Collection"] && ![cls containsString:@"Clip"]) continue;
            NSString *n = XO(it, @"displayName") ?: cls;
            NSString *key = SourceKey(it);
            if ([seen containsObject:key]) continue;   // another item from the same source was already revealed
            [seen addObject:key];
            tried++;
            @try {
                ((void(*)(id,SEL,id))objc_msgSend)(tm, sSet, @[it]);
                id anc = nil; BOOL isNew = NO;
                ((BOOL(*)(id,SEL,id*,BOOL*))objc_msgSend)(tm, sRev, &anc, &isNew);
                if (isNew) added++;
            } @catch (id e) { XL([NSString stringWithFormat:@"skip %@: %@", n, e]); }
        }
        ((void(*)(id,SEL,id))objc_msgSend)(tm, sSet, oldSel);
        XL([NSString stringWithFormat:@"%@: checked %d sources, added %d to browser", XO(seq, @"displayName"), tried, added]);
    } @catch (id e) { XL([NSString stringWithFormat:@"threw %@", e]); }
}
static IMP gOrigImport, gOrigCreate;
static id ActiveSeq(void) { return XO(XO(XO([NSApp delegate], @"activeEditorContainer"), @"timelineModule"), @"sequence"); }
static NSTimer *gWatch;
// The projects the current import created (FFXMLImporter -createSequenceProject:name:error:). A timeline's
// -targetTimelineProject is that same object, which is how we know an open timeline came from this import.
static NSHashTable *gCreated;
static id h_create(id self, SEL _cmd, id xmlProject, id name, id *err) {
    id r = ((id(*)(id,SEL,id,id,id*))gOrigCreate)(self, _cmd, xmlProject, name, err);
    if (r) [gCreated addObject:r];
    return r;
}
static BOOL FromThisImport(id seq, id before) {
    if (!gOrigCreate) return seq != before;   // can't tell on this Final Cut version: any newly opened timeline
    id p = XO(seq, @"targetTimelineProject");
    return p && [gCreated containsObject:p];
}
// After an import, wait briefly for the imported timeline to open, then fill the browser. Final Cut
// opens an imported timeline as soon as the import finishes. Only a timeline this import created counts,
// so a project the user opens instead never gets *its* clips added to the library.
static const int kWatchSeconds = 20;
static void WatchForNewTimeline(id before) {
    __block int ticks = 0;
    __weak id weakBefore = before;
    [gWatch invalidate];
    gWatch = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        ticks++;
        id seq = ActiveSeq();
        if (seq && FromThisImport(seq, weakBefore) && XO(seq, @"primaryObject")) {
            [t invalidate]; gWatch = nil;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AddClipsToBrowser(); });
        } else if (ticks > kWatchSeconds) { [t invalidate]; gWatch = nil; XL(@"no imported timeline opened; nothing added"); }
    }];
}
static id h_import(id self, SEL _cmd, id *err) {
    gCreated = [NSHashTable weakObjectsHashTable];
    // only needed when we can't tell which projects the import made (see FromThisImport)
    id before = (!gOrigCreate && [NSThread isMainThread]) ? ActiveSeq() : nil;
    id r = ((id(*)(id,SEL,id*))gOrigImport)(self, _cmd, err);
    NSUInteger made = gCreated.count;
    if (gOrigCreate && !made) { XL(@"xml import finished; it made no timeline, nothing to add"); return r; }
    XL([NSString stringWithFormat:@"xml import finished (%lu timeline(s)), waiting for one to open", (unsigned long)made]);
    dispatch_async(dispatch_get_main_queue(), ^{ WatchForNewTimeline(before); });
    return r;
}
static void Install(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class C = objc_getClass("FFXMLImporter");
        Method m = C ? class_getInstanceMethod(C, NSSelectorFromString(@"import:")) : NULL;
        if (!m) { XL(@"FFXMLImporter import: not found"); return; }
        gOrigImport = method_setImplementation(m, (IMP)h_import);
        Method mc = class_getInstanceMethod(C, NSSelectorFromString(@"createSequenceProject:name:error:"));
        if (mc && [objc_getClass("FFAnchoredSequence") instancesRespondToSelector:NSSelectorFromString(@"targetTimelineProject")])
            gOrigCreate = method_setImplementation(mc, (IMP)h_create);
        XL(gOrigCreate ? @"xml clips ready" : @"xml clips ready (can't match timelines to imports on this version: any timeline opened right after an import)");
    });
}
__attribute__((visibility("default"))) void SpliceKitPlugin_init(void *ctx) { Install(); }
__attribute__((constructor)) static void ctor(void) { dispatch_async(dispatch_get_main_queue(), ^{ Install(); }); }
