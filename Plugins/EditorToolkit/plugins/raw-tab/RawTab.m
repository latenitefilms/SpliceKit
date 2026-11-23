// RAW Tab: puts Final Cut Pro's own RAW settings controls in their own tab inside the inspector.
// Each RAW family is a "provider" (see kProviders): how to recognise it and which of Final Cut's
// native RAW settings windows edits it. Adding a format = adding one row to kProviders. Built for FCP 12.4 + SpliceKit 3.3.9.
// Tab plumbing modelled on Transcript Tab (github.com/bcassin/fcp-transcript-tab, MIT).
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kTabIdent = @"SKInspectorTabRAWIdentifier";
static void RLog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a);
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/SpliceKit"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    FILE *f = fopen([dir stringByAppendingPathComponent:@"raw-tab.log"].fileSystemRepresentation, "a");
    if (f) { fprintf(f, "%s %s\n", [NSDate date].description.UTF8String, s.UTF8String); fclose(f); }
}

@interface FFInspectorModule : NSResponder
- (void)setCurrentItems:(id)items;
- (void)setView:(NSView *)view;
- (NSView *)view;
@end

@class SKRawTabModule;
static __weak id gTabModule;
static __weak SKRawTabModule *gModule;
static BOOL gOpeningFromTab;
static BOOL gREDUnavailable;   // set when Final Cut has no RED RAW settings button (RED plugin missing)

@interface SKRawContainer : NSView
@property (nonatomic, weak) SKRawTabModule *owner;
@end

@interface SKRawTabModule : FFInspectorModule
@property (nonatomic, strong) SKRawContainer *container;
@property (nonatomic, strong) NSTextField *placeholder;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic) BOOL built;
- (void)sk_refresh;
@end

@implementation SKRawContainer
- (BOOL)isFlipped { return YES; }
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) dispatch_async(dispatch_get_main_queue(), ^{ [self.owner sk_refresh]; });
}
@end

// ---- RAW providers -------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, RFormat) { RFormatNone = 0, RFormatProResRAW, RFormatRED, RFormatRAWProcessor, RFormatMixed };
typedef struct { RFormat fmt; const char *name; const char *hudClass; BOOL embeddable; } RProvider;
// embeddable: the HUD can be pointed at items directly (shared / setAssetItems: / openHUD / panel).
// RED's window is driven by Final Cut's RED controller from the real Info-inspector button, so it is
// only embedded after that native button has opened it (see RLoadREDControls).
static const RProvider kProviders[] = {
    { RFormatProResRAW,    "ProRes RAW",           "FFProResRAWSettingsHud", YES },
    { RFormatRED,          "RED (R3D)",            "FFREDRAWSettings",       NO  },
    { RFormatRAWProcessor, "RAW (BRAW and others)", "FFVTRAWSettingsHud",     YES },
};
static const RProvider *RProviderFor(RFormat f) {
    for (size_t i = 0; i < sizeof(kProviders) / sizeof(kProviders[0]); i++) if (kProviders[i].fmt == f) return &kProviders[i];
    return NULL;
}
static id RCall(id o, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    return (o && [o respondsToSelector:s]) ? ((id(*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static BOOL RBool(id o, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    return (o && [o respondsToSelector:s]) ? ((BOOL(*)(id, SEL))objc_msgSend)(o, s) : NO;
}
static RFormat RFormatOfAsset(id a) {
    @try {
        if (RBool(a, @"isProResRAWCodec")) return RFormatProResRAW;
        id url = RCall(a, @"originalMediaURL");
        if ([url isKindOfClass:[NSURL class]] && [[[(NSURL *)url pathExtension] lowercaseString] isEqualToString:@"r3d"]) return RFormatRED;
        if (RBool(a, @"usingRAWMediaExtension") || RCall(a, @"rawProcessorSettings")) return RFormatRAWProcessor;  // BRAW etc. (unchanged path)
    } @catch (id e) {}
    return RFormatNone;
}
// Format shared by every selected clip; None if any clip isn't RAW, Mixed if RAW formats differ.
static RFormat RFormatOfItems(id items) {
    if (![items respondsToSelector:@selector(countByEnumeratingWithState:objects:count:)]) return RFormatNone;
    SEL as = NSSelectorFromString(@"assetsIncludingAnchored:");
    RFormat common = RFormatNone; NSUInteger n = 0;
    for (id it in items) {
        n++;
        if (![it respondsToSelector:as]) return RFormatNone;
        RFormat f = RFormatNone;
        for (id a in ((id(*)(id, SEL, BOOL))objc_msgSend)(it, as, NO)) { f = RFormatOfAsset(a); if (f) break; }
        if (!f) return RFormatNone;
        if (common && f != common) common = RFormatMixed; else if (!common) common = f;
    }
    return n ? common : RFormatNone;
}
static id RHudFor(const RProvider *p) {
    Class c = p ? objc_getClass(p->hudClass) : Nil;
    return c ? ((id(*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"shared")) : nil;
}

@implementation SKRawTabModule
- (void)sk_build {
    if (self.built) return;
    self.built = YES;
    gModule = self;
    SKRawContainer *c = [[SKRawContainer alloc] initWithFrame:NSMakeRect(0, 0, 400, 600)];
    c.owner = self;
    c.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTextField *ph = [NSTextField wrappingLabelWithString:@"Select a RAW clip to edit its RAW settings."];
    ph.textColor = [NSColor secondaryLabelColor];
    ph.alignment = NSTextAlignmentCenter;
    ph.frame = NSMakeRect(20, 30, 360, 60);
    ph.autoresizingMask = NSViewWidthSizable;
    [c addSubview:ph];
    self.placeholder = ph;
    NSButton *b = [NSButton buttonWithTitle:@"Load RED RAW Controls" target:self action:@selector(sk_loadRED:)];
    b.controlSize = NSControlSizeSmall;
    b.frame = NSMakeRect(120, 96, 160, 24);
    b.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
    b.hidden = YES;
    [c addSubview:b];
    objc_setAssociatedObject(self, "sk_redButton", b, OBJC_ASSOCIATION_RETAIN);
    self.container = c;
    [self setView:c];
}
- (instancetype)init { self = [super init]; if (self) [self sk_build]; return self; }
- (BOOL)loadView { [self sk_build]; return YES; }
- (void)loadNib { [self sk_build]; }
- (BOOL)isNibLoaded { return self.built; }
- (NSView *)view { [self sk_build]; return self.container; }
- (BOOL)shouldDisplayModuleWithItems:(id)items { return YES; }
- (void)setCurrentItems:(id)items {
    @try { [super setCurrentItems:items]; } @catch (id e) { RLog(@"super setCurrentItems threw %@", e); }
    [self sk_build];
    self.items = [items isKindOfClass:[NSArray class]] ? [items copy] : nil;
    if (self.container.window) [self sk_refresh];
}
- (void)sk_message:(NSString *)msg showREDButton:(BOOL)red {
    self.placeholder.stringValue = msg ?: @"";
    self.placeholder.hidden = (msg == nil);
    [(NSButton *)objc_getAssociatedObject(self, "sk_redButton") setHidden:!red];
}
// Show exactly one provider's controls (or none); everything else in the tab is hidden.
- (void)sk_showContent:(NSView *)show {
    for (size_t i = 0; i < sizeof(kProviders) / sizeof(kProviders[0]); i++) {
        id hud = RHudFor(&kProviders[i]);
        NSView *v = hud ? objc_getAssociatedObject(hud, "sk_rawContent") : nil;
        if (v && v != show) v.hidden = YES;
    }
    if (!show) return;
    // Keep each RAW window's own layout: natural size, pinned to the top, centred horizontally.
    // (Stretching it to the tab's height pushed RED's controls to the bottom and left a large gap.)
    NSValue *nat = objc_getAssociatedObject(show, "sk_natural");
    if (!nat) { nat = [NSValue valueWithSize:show.frame.size]; objc_setAssociatedObject(show, "sk_natural", nat, OBJC_ASSOCIATION_RETAIN); }
    NSSize n = nat.sizeValue;
    if (show.superview != self.container) {
        [show removeFromSuperview];
        show.translatesAutoresizingMaskIntoConstraints = YES;
        [self.container addSubview:show];
    }
    CGFloat W = NSWidth(self.container.bounds);
    show.frame = NSMakeRect(MAX(0, floor((W - n.width) / 2)), 8, n.width, n.height);   // container is flipped: y=8 is near the top
    show.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
    show.hidden = NO;
}
- (NSArray *)sk_items {
    NSArray *items = self.items;
    if (!items.count) {
        id tabModule = gTabModule;
        for (NSView *v = self.container.superview; v && !tabModule; v = v.superview)
            if ([v isKindOfClass:[NSTabView class]] && [NSStringFromClass([[(NSTabView *)v delegate] class]) containsString:@"InspectorTab"]) tabModule = [(NSTabView *)v delegate];
        id cur = nil; @try { cur = [tabModule valueForKey:@"currentItems"]; } @catch (id e) {}
        if ([cur isKindOfClass:[NSArray class]]) items = cur;
    }
    return items ?: @[];
}
- (void)sk_refresh {
    if (!self.container.window) return;
    @try {
        NSArray *items = [self sk_items];
        RFormat f = RFormatOfItems(items);
        const RProvider *p = RProviderFor(f);
        RLog(@"refresh with %lu item(s), format=%s", (unsigned long)items.count, p ? p->name : (f == RFormatMixed ? "mixed" : "none"));
        if (f == RFormatMixed) { [self sk_showContent:nil]; [self sk_message:@"The selected clips use different RAW formats.\nSelect clips of one RAW format to edit their RAW settings." showREDButton:NO]; return; }
        if (!p) { [self sk_showContent:nil]; [self sk_message:@"Select a RAW clip to edit its RAW settings." showREDButton:NO]; return; }
        id hud = RHudFor(p);
        if (!hud) { [self sk_showContent:nil]; [self sk_message:[NSString stringWithFormat:@"Final Cut's %s settings aren't available in this version.", p->name] showREDButton:NO]; return; }
        if (!p->embeddable) {
            // RED: the RED controller follows the timeline selection itself once its window is loaded.
            NSView *content = objc_getAssociatedObject(hud, "sk_rawContent");
            if (content) { [self sk_message:nil showREDButton:NO]; [self sk_showContent:content]; }
            else if (gREDUnavailable) { [self sk_showContent:nil]; [self sk_message:@"Final Cut doesn't offer RED RAW settings for this clip.\n\nInstall RED Apple Workflow Installer (from red.com), restart Final Cut, then try again." showREDButton:NO]; }
            else { [self sk_showContent:nil]; [self sk_message:@"RED RAW controls are provided by RED's Apple Workflow plugin for Final Cut." showREDButton:YES]; }
            return;
        }
        NSView *existing = objc_getAssociatedObject(hud, "sk_rawContent");
        NSArray *last = objc_getAssociatedObject(hud, "sk_lastItems");
        if (existing && existing.superview == self.container && !existing.hidden && [last isEqualToArray:items]) return;
        objc_setAssociatedObject(hud, "sk_lastItems", items, OBJC_ASSOCIATION_RETAIN);
        ((void(*)(id, SEL, id))objc_msgSend)(hud, NSSelectorFromString(@"setAssetItems:"), items);
        gOpeningFromTab = YES;
        ((void(*)(id, SEL))objc_msgSend)(hud, NSSelectorFromString(@"openHUD"));   // loads + refreshes; panel is hidden by our hook
        gOpeningFromTab = NO;
        NSPanel *panel = RCall(hud, @"panel");
        NSView *content = objc_getAssociatedObject(hud, "sk_rawContent");
        if (!content && panel) {
            content = panel.contentView;
            panel.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
            objc_setAssociatedObject(hud, "sk_rawContent", content, OBJC_ASSOCIATION_RETAIN);
            RLog(@"moved %s controls into tab (natural size %@)", p->name, NSStringFromSize(content.frame.size));
        }
        [self sk_message:(content ? nil : @"Couldn't load the RAW controls for this clip.") showREDButton:NO];
        [self sk_showContent:content];
        [panel orderOut:nil];
    } @catch (id e) {
        gOpeningFromTab = NO;
        RLog(@"refresh threw %@", e);
    }
}
// RED: press Final Cut's own "Modify RED RAW Settings" button in the Info tab (its real code path);
// the openHUD hook then moves the RED window's controls into this tab.
static NSButton *RFindButton(NSView *v, SEL action) {
    if ([v isKindOfClass:[NSButton class]] && [(NSButton *)v action] == action) return (NSButton *)v;
    for (NSView *s in v.subviews) { NSButton *b = RFindButton(s, action); if (b) return b; }
    return nil;
}
- (void)sk_loadRED:(id)sender {
    @try {
        NSTabView *tv = gTabModule ? [gTabModule valueForKey:@"_tabView"] : nil;
        NSInteger info = -1;
        for (NSUInteger i = 0; i < tv.tabViewItems.count && info < 0; i++) {
            NSTabViewItem *it = tv.tabViewItems[i];
            id ident = it.identifier;
            if ([ident isEqual:@"FFInspectorTabInfoIdentifier"] || [it.label isEqualToString:@"Info"] ||
                [NSStringFromClass([ident class]) containsString:@"FileInfo"]) info = (NSInteger)i;
        }
        if (info < 0) { RLog(@"RED: Info tab not found in %@", tv.tabViewItems); return; }
        ((void(*)(id,SEL,NSUInteger))objc_msgSend)(gTabModule, NSSelectorFromString(@"selectInspectorTab:"), (NSUInteger)info);
        [self sk_pressREDButtonAfter:0.3 triesLeft:5];
    } @catch (id e) { RLog(@"loadRED threw %@", e); }
}
// The Info tab builds its RED button a moment after it is selected, and on a busy or slow machine that can take
// longer than one fixed wait: look for it a few times (~2 s in all) before deciding Final Cut has no RED settings.
- (void)sk_pressREDButtonAfter:(double)delay triesLeft:(int)tries {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            NSButton *b = nil;
            for (NSWindow *w in NSApp.windows) { b = RFindButton(w.contentView, NSSelectorFromString(@"modifyRedRawSettingsButtonPressed:")); if (b) break; }
            if (!b && tries > 0) { [self sk_pressREDButtonAfter:0.35 triesLeft:tries - 1]; return; }
            RLog(@"RED: native button %@", b ? @"found - pressing" : @"not found");
            if (b) [NSApp sendAction:b.action to:b.target from:b];   // Final Cut's own button action, no synthetic click
            else {
                // Without RED's plugin Final Cut plays R3D but has no RED RAW settings at all.
                gREDUnavailable = YES;
                [self sk_message:@"Final Cut doesn't offer RED RAW settings for this clip.\n\nInstall RED Apple Workflow Installer (from red.com), restart Final Cut, then try again." showREDButton:NO];
                NSTabView *tv2 = gTabModule ? [gTabModule valueForKey:@"_tabView"] : nil;
                for (NSUInteger i = 0; i < tv2.tabViewItems.count; i++)
                    if (tv2.tabViewItems[i].identifier == gModule || [tv2.tabViewItems[i].identifier isEqual:kTabIdent]) {
                        ((void(*)(id,SEL,NSUInteger))objc_msgSend)(gTabModule, NSSelectorFromString(@"selectInspectorTab:"), i); break; }
            }
        } @catch (id e) { RLog(@"RED button lookup threw %@", e); }
    });
}
@end

static IMP o_ids, o_image, o_alt, o_button;
static NSMutableDictionary<NSString *, NSValue *> *gOpenHUD;   // HUD class name -> original -openHUD

// Final Cut's inspector shows at most 5 tabs. When the identifier list for a selection is longer,
// it silently falls back to just Video + Info - which is how titles lost their Title tab (and clips
// their Color/Audio tabs) once the RAW tab was being added to every selection. So:
//   - the RAW tab is only added for clips whose media really is RAW (any provider in kProviders)
//   - native tabs are never displaced; if the list is already full, only another plugin's tab
//     (e.g. Transcript) gives up its place for the RAW tab, otherwise the RAW tab is left out.
static const NSUInteger kMaxInspectorTabs = 5;
static BOOL RItemsAreRAW(id items) { return RFormatOfItems(items) != RFormatNone; }   // includes mixed RAW selections
static BOOL RIsNative(id k) { return [k isKindOfClass:[NSString class]] ? [k hasPrefix:@"FF"] : YES; }

static BOOL h_ids(id self, SEL _cmd, id items, __autoreleasing id *outIds, __autoreleasing id *outMap) {
    BOOL r = ((BOOL(*)(id,SEL,id,__autoreleasing id*,__autoreleasing id*))o_ids)(self,_cmd,items,outIds,outMap);
    @try {
        gTabModule = self;
        if (!r || !outIds || !outMap || !*outIds || !*outMap) return r;
        BOOL ordered = [*outIds isKindOfClass:[NSOrderedSet class]];
        NSMutableArray *ids = [(ordered ? [(NSOrderedSet *)*outIds array] : (NSArray *)*outIds) mutableCopy];
        NSMapTable *map = *outMap;
        BOOL had = [ids containsObject:kTabIdent];
        [ids removeObject:kTabIdent];
        BOOL want = ![ids containsObject:@"FFInspectorTabLibraryPropertiesIdentifier"]
                 && ![ids containsObject:@"FFInspectorTabProjectPropertiesIdentifier"]
                 && [ids containsObject:@"FFInspectorTabInfoIdentifier"]
                 && RItemsAreRAW(items);
        if (want && ids.count >= kMaxInspectorTabs) {
            for (NSInteger i = (NSInteger)ids.count - 1; i >= 0 && ids.count >= kMaxInspectorTabs; i--)
                if (!RIsNative(ids[i])) { RLog(@"tab limit: %@ makes room for RAW", ids[i]); [ids removeObjectAtIndex:i]; }
            if (ids.count >= kMaxInspectorTabs) { want = NO; RLog(@"tab limit: no room for RAW tab (%lu native tabs)", (unsigned long)ids.count); }
        }
        if (want) {
            id sample = [map objectForKey:ids.firstObject];
            id value;
            if ([sample isKindOfClass:[NSArray class]]) value = @[@"SKRawTabModule"];
            else if ([sample isKindOfClass:[NSString class]]) value = @"SKRawTabModule";
            else value = [SKRawTabModule class];
            [map setObject:value forKey:kTabIdent];
            [ids addObject:kTabIdent];
        } else if (had) [map removeObjectForKey:kTabIdent];
        // safety net for any plugin tab: never let the list grow past what Final Cut can show
        for (NSInteger i = (NSInteger)ids.count - 1; i >= 0 && ids.count > kMaxInspectorTabs; i--)
            if (!RIsNative(ids[i]) && ![ids[i] isEqual:kTabIdent]) { RLog(@"tab limit: dropped %@ so native tabs stay", ids[i]); [ids removeObjectAtIndex:i]; }
        if (want || had || ids.count != ([*outIds count])) *outIds = ordered ? (id)[NSOrderedSet orderedSetWithArray:ids] : (id)[ids copy];
    } @catch (id e) { RLog(@"h_ids threw %@", e); }
    return r;
}
static NSImage *RTabImage(void) {
    static NSImage *img;
    if (img) return img;
    NSImage *sym = [[NSImage imageWithSystemSymbolName:@"camera.aperture" accessibilityDescription:@"RAW"]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular]];
    img = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect r) {
        NSSize s = sym.size; CGFloat k = MIN(15 / MAX(s.width, 1), 15 / MAX(s.height, 1));
        NSSize f = NSMakeSize(s.width * k, s.height * k);
        [sym drawInRect:NSMakeRect((18 - f.width) / 2, (18 - f.height) / 2, f.width, f.height)];
        return YES;
    }];
    img.template = YES;
    return img;
}
static id h_image(id self, SEL _cmd, id tab) {
    if ([tab isKindOfClass:[NSString class]] && [tab isEqualToString:kTabIdent]) return RTabImage();
    return ((id(*)(id,SEL,id))o_image)(self,_cmd,tab);
}
static id h_alt(id self, SEL _cmd, id tab) {
    if (!([tab isKindOfClass:[NSString class]] && [tab isEqualToString:kTabIdent])) return ((id(*)(id,SEL,id))o_alt)(self,_cmd,tab);
    static NSImage *tinted;
    if (!tinted) {
        NSImage *g = RTabImage(); NSColor *c = [NSColor controlAccentColor];
        tinted = [NSImage imageWithSize:g.size flipped:NO drawingHandler:^BOOL(NSRect r) {
            [g drawInRect:r]; [c set]; NSRectFillUsingOperation(r, NSCompositingOperationSourceAtop); return YES; }];
    }
    return tinted;
}
static id h_button(id self, SEL _cmd, id title, long tag) {
    return ((id(*)(id,SEL,id,long))o_button)(self,_cmd,title ?: @"RAW",tag);
}
// The Info tab's "Edit RAW Properties" button: jump to our tab instead of showing the floating window.
static void h_openHUD(id self, SEL _cmd) {
    IMP orig = NULL;
    for (Class k = [self class]; k && !orig; k = class_getSuperclass(k)) orig = [gOpenHUD[NSStringFromClass(k)] pointerValue];
    if (orig) ((void(*)(id,SEL))orig)(self, _cmd);
    @try {
        NSPanel *panel = ((id(*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"panel"));
        NSView *content = objc_getAssociatedObject(self, "sk_rawContent");
        if (gOpeningFromTab) { if (content) [panel orderOut:nil]; return; }
        if (!content && panel && [NSStringFromClass([self class]) isEqualToString:@"FFREDRAWSettings"] && gModule) {
            content = panel.contentView;   // first time the RED window opens: bring its controls into the tab
            panel.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
            objc_setAssociatedObject(self, "sk_rawContent", content, OBJC_ASSOCIATION_RETAIN);
            RLog(@"moved RED controls into tab (natural size %@)", NSStringFromSize(content.frame.size));
        }
        NSInteger tab = -1;
        NSTabView *tv = gTabModule ? [gTabModule valueForKey:@"_tabView"] : nil;
        for (NSUInteger i = 0; i < tv.tabViewItems.count; i++) {
            NSTabViewItem *it = tv.tabViewItems[i];
            if ([it.identifier isEqual:kTabIdent] || (gModule && it.identifier == gModule)) { tab = (NSInteger)i; break; }
        }
        if (tab >= 0) {
            if (content) [panel orderOut:nil];
            ((void(*)(id,SEL,NSUInteger))objc_msgSend)(gTabModule, NSSelectorFromString(@"selectInspectorTab:"), (NSUInteger)tab);
            dispatch_async(dispatch_get_main_queue(), ^{ [gModule sk_refresh]; });
        } else if (content && panel) {
            // no RAW tab for this selection: give the controls back to Final Cut's own floating window
            [content removeFromSuperview];
            content.hidden = NO;
            panel.contentView = content;
            objc_setAssociatedObject(self, "sk_rawContent", nil, OBJC_ASSOCIATION_RETAIN);
            [panel makeKeyAndOrderFront:nil];
            RLog(@"no RAW tab here - showing the native RAW window");
        }
    } @catch (id e) { RLog(@"openHUD hook threw %@", e); }
}
static IMP hook(Class c, NSString *sel, IMP n) {
    Method m = class_getInstanceMethod(c, NSSelectorFromString(sel));
    if (!m) { RLog(@"missing %@", sel); return NULL; }
    return method_setImplementation(m, n);
}
__attribute__((visibility("default"))) void SpliceKitPlugin_init(void *api) { (void)api; }
static void rawtab_install(void) {
    static BOOL done; if (done) return; done = YES;
    Class c = objc_getClass("FFInspectorTabModule");
    if (!c) { RLog(@"missing FFInspectorTabModule"); return; }
    gOpenHUD = [NSMutableDictionary dictionary];
    o_ids = hook(c, @"_identifiersAndClassesForItems:outTabIdentifiers:outClassesMap:", (IMP)h_ids);
    o_image = hook(c, @"imageForInspectorTab:", (IMP)h_image);
    o_alt = hook(c, @"altImageForInspectorTab:", (IMP)h_alt);
    o_button = hook(c, @"newTabSelectorButtonWithTitle:tag:", (IMP)h_button);
    for (size_t i = 0; i < sizeof(kProviders) / sizeof(kProviders[0]); i++) {
        Class h = objc_getClass(kProviders[i].hudClass);
        Method m = h ? class_getInstanceMethod(h, @selector(openHUD)) : NULL;
        if (!m) { RLog(@"%s: %s not available", kProviders[i].name, kProviders[i].hudClass); continue; }
        if (method_getImplementation(m) == (IMP)h_openHUD) continue;   // shared/inherited openHUD already hooked
        // record the original under the class that defines this openHUD (it may be inherited), so h_openHUD finds it
        // from every subclass that shares it - not just the first provider that happened to be hooked
        Class owner = h;
        for (Class sup = class_getSuperclass(h); sup && class_getInstanceMethod(sup, @selector(openHUD)) == m; sup = class_getSuperclass(sup)) owner = sup;
        gOpenHUD[NSStringFromClass(owner)] = [NSValue valueWithPointer:(void *)method_setImplementation(m, (IMP)h_openHUD)];
    }
    RLog(@"RAW Tab loaded (ids=%d image=%d alt=%d button=%d) providers=%@", o_ids != NULL, o_image != NULL, o_alt != NULL, o_button != NULL, gOpenHUD.allKeys);
}
// hook after every other plugin has loaded, so our tab is added on top of theirs (e.g. transcript tab)
__attribute__((constructor)) static void rawtab_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ rawtab_install(); });
}
