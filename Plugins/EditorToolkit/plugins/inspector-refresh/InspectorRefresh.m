// Inspector Refresh: after something is dropped into the timeline (e.g. dragging a clip from the Browser onto an
// existing one), Final Cut can leave the Inspector attached to the clip that was just replaced, which is no longer
// in use: edits in the Inspector (Scale, Position ...) then change nothing you can see. Shortly after a drop, give
// the dropped clips their own Transform and rebuild the Inspector from what the clips really use.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void RLog(NSString *s) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/SpliceKit"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *p = [dir stringByAppendingPathComponent:@"inspector-refresh.log"];
    FILE *f = fopen(p.fileSystemRepresentation, "a");
    if (f) { fprintf(f, "%s %s\n", [NSDate date].description.UTF8String, s.UTF8String); fclose(f); }
}
static id O(id o, NSString *sel) { SEL s = NSSelectorFromString(sel); return (o && [o respondsToSelector:s]) ? ((id(*)(id, SEL))objc_msgSend)(o, s) : nil; }

// Final Cut can swap a clip's built-in effects (Transform, Crop ...) for new objects just after a drop, without
// telling the Inspector, which keeps showing controls built from the old ones: edits then go to effects the clip no
// longer uses. Ask every channel Inspector (Video, Color ...) to rebuild from the clips' current effects. This does
// not touch the selection, so it never fights with what you click next.
static void Collect(id module, NSMutableArray *out, int depth) {
    if (!module || depth > 6) return;
    if ([module isKindOfClass:objc_getClass("FFInspectorModuleChannels")]) [out addObject:module];
    for (id sub in (NSArray *)O(module, @"submodules")) Collect(sub, out, depth + 1);
}
static void Rebuild(NSString *why) {
    @try {
        id root = ((id(*)(id, SEL, id))objc_msgSend)(objc_getClass("LKViewModule"), @selector(installedModuleWithIdentifier:), @"PEMainInspectorContainer");
        NSMutableArray *mods = [NSMutableArray array]; Collect(root, mods, 0);
        SEL fr = NSSelectorFromString(@"forceInspectorRebuild");
        NSUInteger n = 0;
        for (id m in mods) if ([m respondsToSelector:fr] && [(NSArray *)O(m, @"currentItems") count]) { ((void(*)(id, SEL))objc_msgSend)(m, fr); n++; }
        RLog([NSString stringWithFormat:@"%@: rebuilt %lu Inspector section(s) from the clips' current effects", why, (unsigned long)n]);
    } @catch (NSException *e) { RLog([NSString stringWithFormat:@"rebuild threw %@", e.reason]); }
}

// The real cause: a clip that was just dropped in has no Transform effect of its own yet (Final Cut makes one on
// the first edit). Until then the Inspector shows a shared stand-in Transform, and edits to Scale/Position go
// into that stand-in instead of creating the clip's own - so nothing changes on screen. Give every newly dropped
// video clip its own default Transform (identity: the picture does not change), then rebuild the Inspector.
static BOOL HasVideo(id item) {
    SEL s = NSSelectorFromString(@"hasVideo");
    return [item respondsToSelector:s] ? ((BOOL(*)(id, SEL))objc_msgSend)(item, s) : YES;
}
static id ActiveTM(void) { return O(O([NSApp delegate], @"activeEditorContainer"), @"timelineModule"); }
// Every clip in a timeline by identity - spine items, what's connected to them, and the clips inside connected
// storylines. Taken just before a drop, it tells us afterwards which clips the drop added.
static NSHashTable *TimelineClips(id seq) {
    NSHashTable *h = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
    for (id it in (NSArray *)O(O(seq, @"primaryObject"), @"containedItems")) {
        [h addObject:it];
        for (id a in (NSSet *)O(it, @"anchoredItems")) { [h addObject:a]; for (id inner in (NSArray *)O(a, @"containedItems")) [h addObject:inner]; }
    }
    return h;
}
// `before`: the timeline's clips just before the drop, in sequence `seq0`
static void EnsureTransform(NSString *why, id seq0, NSHashTable *before) {
    @try {
        id tm = ActiveTM();
        if (!seq0 || !before || O(tm, @"sequence") != seq0) return;   // no timeline then, or another one is open now
        // Only clips the drop added, and only if they're explicitly selected (Final Cut selects what you drop).
        // Not clips that were selected or in the timeline before (a click in the moments after a drop, or an
        // ordinary move of clips already there), and not Final Cut's implicit pick under the playhead, which
        // plain -selectedItems also returns when nothing is selected.
        SEL explicitSel = NSSelectorFromString(@"selectedItems:includeItemBeforePlayheadIfLast:");
        if (![tm respondsToSelector:explicitSel]) { RLog(@"no selectedItems:includeItemBeforePlayheadIfLast: on the timeline - can't tell which clips were dropped"); return; }
        NSArray *sel = ((id(*)(id, SEL, BOOL, BOOL))objc_msgSend)(tm, explicitSel, NO, NO);
        if (![sel isKindOfClass:[NSArray class]]) return;
        NSUInteger added = 0;
        SEL add = NSSelectorFromString(@"addIntrinsicEffectForEffectID:"), xf = NSSelectorFromString(@"xform3DEffect");
        SEL ab = NSSelectorFromString(@"actionBegin:animationHint:deferUpdates:"), ae = NSSelectorFromString(@"actionEnd:save:error:");
        // one sequence action around every clip's change, so a multi-clip drop is one Undo step, not one per clip
        id seq = O(tm, @"sequence");
        BOOL wrap = [seq respondsToSelector:ab] && [seq respondsToSelector:ae], began = NO;
        @try {
            for (id item in sel) {
                if ([before containsObject:item] || !HasVideo(item)) continue;
                id stack = [item isKindOfClass:objc_getClass("FFAnchoredCollection")] ? O(item, @"videoEffects") : O(item, @"effectStack");
                if (!stack || ![stack respondsToSelector:add] || ![stack respondsToSelector:xf] || O(stack, @"xform3DEffect")) continue;
                if (wrap && !began) { ((void(*)(id, SEL, id, id, BOOL))objc_msgSend)(seq, ab, @"Transform", nil, NO); began = YES; }
                ((void(*)(id, SEL, id, id, BOOL))objc_msgSend)(stack, ab, @"Transform", nil, YES);
                @try { ((id(*)(id, SEL, id))objc_msgSend)(stack, add, @"HEXForm3D"); added++; }
                @finally { ((BOOL(*)(id, SEL, id, BOOL, id *))objc_msgSend)(stack, ae, @"Transform", YES, NULL); }
            }
        } @finally {
            if (began) ((BOOL(*)(id, SEL, id, BOOL, id *))objc_msgSend)(seq, ae, @"Transform", YES, NULL);
        }
        if (added) RLog([NSString stringWithFormat:@"%@: gave %lu dropped clip(s) their own Transform", why, (unsigned long)added]);
    } @catch (NSException *e) { RLog([NSString stringWithFormat:@"transform threw %@", e.reason]); }
}

static IMP oConclude;
static void hConclude(id self, SEL _cmd, id info) {
    id seq = O(ActiveTM(), @"sequence");
    NSHashTable *before = nil;
    @try { before = seq ? TimelineClips(seq) : nil; } @catch (NSException *e) { RLog([NSString stringWithFormat:@"snapshot threw %@", e.reason]); }
    ((void(*)(id, SEL, id))oConclude)(self, _cmd, info);
    __weak id wseq = seq;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ EnsureTransform(@"drop into timeline", wseq, before); Rebuild(@"drop into timeline"); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Rebuild(@"drop into timeline (late check)"); });
}

__attribute__((visibility("default"))) void SpliceKitPlugin_init(void *api) { (void)api; }
__attribute__((constructor)) static void inspector_refresh_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static BOOL done; if (done) return; done = YES;
        Method m = class_getInstanceMethod(objc_getClass("TLKTimelineView"), @selector(concludeDragOperation:));
        if (!m) { RLog(@"TLKTimelineView concludeDragOperation: not found - disabled"); return; }
        oConclude = method_setImplementation(m, (IMP)hConclude);
        RLog(@"inspector refresh ready");
    });
}
