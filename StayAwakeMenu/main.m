#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#import <libproc.h>
#import <signal.h>
#import <math.h>
#import "UpdateRelease.h"

static const CGFloat StatusIconPointSize = 16.0;

static NSBundle *PreferredLocalizationBundle(void) {
    NSArray<NSString *> *supportedLocalizations = @[@"en", @"zh-Hans"];
    NSString *localization = [NSBundle preferredLocalizationsFromArray:supportedLocalizations].firstObject ?: @"en";
    NSString *path = [NSBundle.mainBundle pathForResource:localization ofType:@"lproj"];
    return path ? [NSBundle bundleWithPath:path] : NSBundle.mainBundle;
}

static NSString *LocalizedString(NSString *key) {
    return [PreferredLocalizationBundle() localizedStringForKey:key value:key table:nil];
}

// Accumulate trackpad movement; one wheel notch changes one unit.
@interface TimeScrollAccumulator : NSObject
@property(nonatomic) CGFloat remainder;
- (NSInteger)stepsForEvent:(NSEvent *)event;
@end
@implementation TimeScrollAccumulator
- (NSInteger)stepsForEvent:(NSEvent *)event {
    if (event.momentumPhase != NSEventPhaseNone) return 0;
    if (event.phase == NSEventPhaseBegan) self.remainder = 0;
    CGFloat delta = event.scrollingDeltaY;
    if (!event.hasPreciseScrollingDeltas) return delta > 0 ? 1 : delta < 0 ? -1 : 0;
    if (delta * self.remainder < 0) self.remainder = 0;
    self.remainder += delta;
    NSInteger steps = (NSInteger)(self.remainder / 12.0);
    self.remainder -= steps * 12.0;
    return steps;
}
@end

@interface ScrollableTimePicker : NSDatePicker
@property(nonatomic, strong) TimeScrollAccumulator *scrollAccumulator;
@end
@implementation ScrollableTimePicker
- (void)scrollWheel:(NSEvent *)event {
    if (!self.scrollAccumulator) self.scrollAccumulator = [TimeScrollAccumulator new];
    NSInteger steps = [self.scrollAccumulator stepsForEvent:event];
    // Let AppKit increment the selected time segment, including locale-specific AM/PM.
    [self.window makeFirstResponder:self];
    for (NSInteger index = 0; index < labs(steps); index++) {
        NSString *arrow = [NSString stringWithFormat:@"%C", (unichar)(steps > 0 ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)];
        NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
            modifierFlags:0 timestamp:event.timestamp windowNumber:self.window.windowNumber
            context:nil characters:arrow charactersIgnoringModifiers:arrow isARepeat:NO keyCode:steps > 0 ? 126 : 125];
        [self keyDown:key];
    }
    [self sendAction:self.action to:self.target];
}
@end

@interface RoundedTimePresetButton : NSButton
@property(nonatomic) BOOL presetSelected;
@end
@implementation RoundedTimePresetButton
- (void)setPresetSelected:(BOOL)selected {
    _presetSelected = selected;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:@{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: selected ? NSColor.whiteColor : NSColor.labelColor,
        NSParagraphStyleAttributeName: paragraph
    }];
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    BOOL selected = self.presetSelected;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:11 yRadius:11];
    [(selected ? NSColor.controlAccentColor : NSColor.controlBackgroundColor) setFill];
    [shape fill];
    [(selected ? NSColor.controlAccentColor : NSColor.separatorColor) setStroke];
    shape.lineWidth = 0.5;
    [shape stroke];
    [super drawRect:dirtyRect];
}
@end

@interface ScrollableDurationField : NSTextField
@property(nonatomic, strong) TimeScrollAccumulator *scrollAccumulator;
@end
@implementation ScrollableDurationField
- (void)scrollWheel:(NSEvent *)event {
    if (!self.scrollAccumulator) self.scrollAccumulator = [TimeScrollAccumulator new];
    NSInteger steps = [self.scrollAccumulator stepsForEvent:event];
    if (!steps) return;
    // Commit a currently edited field before applying changes to its value.
    [self.window makeFirstResponder:nil];
    for (NSInteger index = 0; index < labs(steps); index++) {
        NSString *candidate = [NSString stringWithFormat:@"%ld", self.integerValue + (steps > 0 ? 1 : -1)];
        if (![self.formatter isPartialStringValid:candidate newEditingString:NULL errorDescription:NULL]) break;
        self.stringValue = candidate;
    }
    NSStepper *stepper = [self.superview viewWithTag:self.tag + 10];
    stepper.integerValue = self.integerValue;
}
@end

// Validate edits before AppKit accepts typing or pasted text.
@interface DurationFormatter : NSFormatter
@property(nonatomic, weak) NSTextField *field;
@end

@implementation DurationFormatter
- (NSString *)stringForObjectValue:(id)object { return [object description] ?: @""; }
- (BOOL)getObjectValue:(out id *)object forString:(NSString *)string errorDescription:(out NSString **)error {
    (void)error;
    if (object) *object = string;
    return YES;
}
- (BOOL)isPartialStringValid:(NSString *)string newEditingString:(NSString **)replacement errorDescription:(NSString **)error {
    (void)replacement;
    (void)error;
    // An empty field is allowed while replacing its contents.
    if (string.length == 0) return YES;
    if (string.length > (self.field.tag == 1 ? 3 : 2) ||
        [string rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound) return NO;
    NSTextField *other = [self.field.superview viewWithTag:self.field.tag == 1 ? 2 : 1];
    NSInteger hours = self.field.tag == 1 ? string.integerValue : other.integerValue;
    NSInteger minutes = self.field.tag == 2 ? string.integerValue : other.integerValue;
    return hours <= 168 && minutes <= 59 && hours * 60 + minutes <= 10080 &&
        (hours + minutes > 0 || other.stringValue.length == 0);
}
@end

@interface StayAwakeApp : NSObject <NSApplicationDelegate, NSMenuDelegate, NSTextFieldDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSImage *runningStatusImage;
@property(nonatomic, strong) NSImage *stoppedStatusImage;
@property(nonatomic, strong) NSMenuItem *statusMenuItem;
@property(nonatomic, strong) NSMenuItem *toggleMenuItem;
@property(nonatomic, strong) NSMenuItem *durationMenuItem;
@property(nonatomic, strong) NSMenuItem *extendMenuItem;
@property(nonatomic, strong) NSTask *startedTask;
@property(nonatomic, strong) NSDate *startedDeadline;
@property(nonatomic, strong) NSMenuItem *aboutMenuItem;
@property(nonatomic, strong) NSMenuItem *quitMenuItem;
@property(nonatomic, strong) NSTimer *refreshTimer;
@property(nonatomic, strong) NSDatePicker *untilPicker;
@property(nonatomic, strong) NSArray<RoundedTimePresetButton *> *untilPresets;
@property(nonatomic, strong) NSTextField *untilPreview;
@property(nonatomic, strong) NSWindow *aboutWindow;
@property(nonatomic, strong) NSButton *checkUpdatesButton;
@property(nonatomic, strong) NSTextField *updateStatus;
@property(nonatomic, strong) NSURLSession *updateSession;
@end

@implementation StayAwakeApp

- (NSURL *)applicationSupportDirectory {
    NSArray<NSURL *> *urls = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
    NSURL *baseURL = urls.firstObject;
    NSString *directoryName = NSBundle.mainBundle.bundleIdentifier ?: @"StayAwake";
    return [baseURL URLByAppendingPathComponent:directoryName isDirectory:YES];
}

- (NSURL *)scriptsDirectory {
    return [[self applicationSupportDirectory] URLByAppendingPathComponent:@"Scripts" isDirectory:YES];
}

- (NSURL *)stateDirectory {
    return [[self applicationSupportDirectory] URLByAppendingPathComponent:@"State" isDirectory:YES];
}

- (NSURL *)logsDirectory {
    return [[self applicationSupportDirectory] URLByAppendingPathComponent:@"Logs" isDirectory:YES];
}

- (NSURL *)bundledHelperURL {
    return [NSBundle.mainBundle URLForResource:@"stay-awake" withExtension:nil subdirectory:@"Scripts"];
}

- (NSURL *)installedHelperURL {
    return [[self scriptsDirectory] URLByAppendingPathComponent:@"stay-awake"];
}

- (NSURL *)pidFile {
    return [[self stateDirectory] URLByAppendingPathComponent:@"caffeinate.pid"];
}

- (NSURL *)sessionFile {
    return [[self stateDirectory] URLByAppendingPathComponent:@"session.plist"];
}

- (NSURL *)logFile {
    return [[self logsDirectory] URLByAppendingPathComponent:@"stay-awake.log"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self configureApplicationIcon];
    [self requestNotificationPermission];
    NSError *error = nil;
    if (![self installHelperIfNeededWithError:&error]) {
        [self showAlert:LocalizedString(@"alert.installHelper.title") detail:error.localizedDescription];
    }
    [self configureStatusItem];
    [self refreshStatus];
    self.refreshTimer = [NSTimer timerWithTimeInterval:5 target:self selector:@selector(refreshStatus) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceDidWake:) name:NSWorkspaceDidWakeNotification object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.updateSession invalidateAndCancel];
    [self.refreshTimer invalidate];
    [self stopStayAwake];
}

- (NSImage *)applicationIcon {
    NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"AppIcon" withExtension:@"icns"];
    NSImage *icon = iconURL ? [[NSImage alloc] initWithContentsOfURL:iconURL] : nil;
    return icon ?: [NSImage imageNamed:@"AppIcon"];
}

- (void)configureApplicationIcon {
    NSImage *icon = [self applicationIcon];
    if (icon) {
        NSApp.applicationIconImage = icon;
    }
}

- (void)configureStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.autosaveName = @"local.stay-awake.menu.status-item";

    NSStatusBarButton *button = self.statusItem.button;
    button.image = [self statusBarImageForRunning:NO];
    button.imagePosition = NSImageLeft;
    button.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    // Keep the symbol at its configured size when the countdown changes button width.
    button.imageScaling = NSImageScaleNone;
    if (@available(macOS 11.0, *)) {
        button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:StatusIconPointSize weight:NSFontWeightRegular scale:NSImageSymbolScaleMedium];
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:LocalizedString(@"app.name")];
    menu.autoenablesItems = NO;
    menu.delegate = self;

    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;

    self.toggleMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(toggleStayAwake:) keyEquivalent:@""];
    self.toggleMenuItem.target = self;
    self.toggleMenuItem.image = nil;

    self.aboutMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(presentStayAwakeAboutPanel:) keyEquivalent:@""];
    self.aboutMenuItem.target = self;
    self.aboutMenuItem.image = nil;
    self.aboutMenuItem.state = NSControlStateValueOff;

    self.quitMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(quit:) keyEquivalent:@"q"];
    self.quitMenuItem.target = self;
    self.quitMenuItem.image = nil;
    self.quitMenuItem.state = NSControlStateValueOff;

    [menu addItem:self.statusMenuItem];
    [menu addItem:self.toggleMenuItem];
    self.durationMenuItem = [[NSMenuItem alloc] initWithTitle:LocalizedString(@"menu.duration") action:nil keyEquivalent:@""];
    NSMenu *durations = [[NSMenu alloc] initWithTitle:LocalizedString(@"menu.duration")];
    for (NSNumber *minutes in @[@15, @30, @60, @120, @180, @240, @300, @480, @0]) {
        NSString *title = minutes.integerValue == 0 ? LocalizedString(@"duration.indefinite") :
            [NSString stringWithFormat:LocalizedString(minutes.integerValue == 60 ? @"duration.hour" :
                (minutes.integerValue > 60 ? @"duration.hours" : @"duration.minutes")),
                minutes.integerValue >= 60 ? minutes.integerValue / 60 : minutes.integerValue];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(startPreset:) keyEquivalent:@""];
        item.target = self;
        item.tag = minutes.integerValue * 60;
        [durations addItem:item];
    }
    [durations addItem:NSMenuItem.separatorItem];
    NSMenuItem *custom = [[NSMenuItem alloc] initWithTitle:LocalizedString(@"duration.custom") action:@selector(startCustom:) keyEquivalent:@""];
    custom.target = self;
    [durations addItem:custom];
    self.durationMenuItem.submenu = durations;
    [menu addItem:self.durationMenuItem];
    NSMenuItem *untilItem = [[NSMenuItem alloc] initWithTitle:LocalizedString(@"until.title") action:@selector(startUntil:) keyEquivalent:@""];
    untilItem.target = self;
    [menu addItem:untilItem];
    self.extendMenuItem = [[NSMenuItem alloc] initWithTitle:LocalizedString(@"menu.extend") action:@selector(extendSession:) keyEquivalent:@""];
    self.extendMenuItem.target = self;
    [menu addItem:self.extendMenuItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:self.aboutMenuItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:self.quitMenuItem];

    [self updateLocalizedMenuText];
    [self applyStatusPresentationForRunning:[self stayAwakeIsRunningOrStarting]];
    self.statusItem.menu = menu;
}

- (NSImage *)statusBarImageForRunning:(BOOL)isRunning {
    NSImage *cachedImage = isRunning ? self.runningStatusImage : self.stoppedStatusImage;
    if (cachedImage) return cachedImage;
    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        NSString *symbolName = isRunning ? @"moon.stars.fill" : @"moon.zzz.fill";
        image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:LocalizedString(@"app.name")];
        NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:StatusIconPointSize weight:NSFontWeightRegular scale:NSImageSymbolScaleMedium];
        image = [image imageWithSymbolConfiguration:configuration] ?: image;
    }
    image = image ?: [NSImage imageNamed:NSImageNameActionTemplate];
    image.template = YES;
    if (isRunning) self.runningStatusImage = image;
    else self.stoppedStatusImage = image;
    return image;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [self refreshStatus];
}

- (void)updateLocalizedMenuText {
    NSString *aboutTitle = LocalizedString(@"menu.about");
    if (![self.aboutMenuItem.title isEqualToString:aboutTitle]) self.aboutMenuItem.title = aboutTitle;
    if (self.aboutMenuItem.image) self.aboutMenuItem.image = nil;
    if (self.aboutMenuItem.state != NSControlStateValueOff) self.aboutMenuItem.state = NSControlStateValueOff;
    NSString *quitTitle = LocalizedString(@"menu.quit");
    if (![self.quitMenuItem.title isEqualToString:quitTitle]) self.quitMenuItem.title = quitTitle;
    if (self.quitMenuItem.image) self.quitMenuItem.image = nil;
    if (self.quitMenuItem.state != NSControlStateValueOff) self.quitMenuItem.state = NSControlStateValueOff;
}

- (void)workspaceDidWake:(NSNotification *)notification {
    (void)notification;
    [self refreshStatus];
}

// Metadata belongs to a particular process. A CLI toggle can replace that process.
- (NSDate *)activeDeadline {
    pid_t pid = [self runningPid];
    if (self.startedTask.running && self.startedTask.processIdentifier == pid) {
        return self.startedDeadline;
    }
    NSDictionary *session = [NSDictionary dictionaryWithContentsOfURL:[self sessionFile]];
    if (pid > 0 && [session[@"pid"] intValue] == pid && [session[@"deadline"] isKindOfClass:NSDate.class]) {
        return session[@"deadline"];
    }
    return nil;
}

- (NSString *)countdownForSeconds:(NSTimeInterval)seconds {
    if (seconds < 60) return LocalizedString(@"countdown.lessThanMinute");
    NSInteger minutes = (NSInteger)ceil(seconds / 60.0);
    if (minutes < 60) return [NSString stringWithFormat:LocalizedString(@"countdown.minutes"), minutes];
    return [NSString stringWithFormat:LocalizedString(@"countdown.hoursMinutes"), minutes / 60, minutes % 60];
}

- (void)refreshStatus {
    NSDate *deadline = [self activeDeadline];
    if (deadline && deadline.timeIntervalSinceNow <= 0) {
        // Reconcile after system sleep too: an expired session must not restart.
        [self stopStayAwakeNotifying:NO];
    }
    [self updateLocalizedMenuText];
    [self applyStatusPresentationForRunning:[self stayAwakeIsRunningOrStarting]];
}

- (void)applyStatusPresentationForRunning:(BOOL)isRunning {
    NSString *toggleTitle = LocalizedString(isRunning ? @"menu.toggle.off" : @"menu.toggle.on");
    if (![self.toggleMenuItem.title isEqualToString:toggleTitle]) self.toggleMenuItem.title = toggleTitle;
    if (self.toggleMenuItem.image) self.toggleMenuItem.image = nil;
    // This item names an action; current status is shown separately.
    if (self.toggleMenuItem.state != NSControlStateValueOff) self.toggleMenuItem.state = NSControlStateValueOff;

    NSStatusBarButton *button = self.statusItem.button;
    NSImage *image = [self statusBarImageForRunning:isRunning];
    if (button.image != image) button.image = image;
    NSDate *deadline = isRunning ? [self activeDeadline] : nil;
    NSString *statusText = deadline ? [self countdownForSeconds:MAX(0, deadline.timeIntervalSinceNow)] : LocalizedString(@"countdown.indefinite");
    NSString *buttonTitle = [@" " stringByAppendingString:isRunning ? statusText : LocalizedString(@"countdown.off")];
    if (![button.title isEqualToString:buttonTitle]) button.title = buttonTitle;
    BOOL canExtend = isRunning && deadline != nil && deadline.timeIntervalSinceNow > 0;
    if (self.extendMenuItem.enabled != canExtend) self.extendMenuItem.enabled = canExtend;
    NSString *menuTitle;
    if (deadline) {
        NSString *endTime = [NSDateFormatter localizedStringFromDate:deadline dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
        menuTitle = [NSString stringWithFormat:LocalizedString(@"menu.status.timed"), statusText, endTime];
    } else {
        menuTitle = LocalizedString(isRunning ? @"menu.status.indefinite" : @"menu.status.off");
    }
    if (![self.statusMenuItem.title isEqualToString:menuTitle]) self.statusMenuItem.title = menuTitle;
    if (self.statusMenuItem.state != NSControlStateValueOff) self.statusMenuItem.state = NSControlStateValueOff;
    NSString *toolTip = deadline ? menuTitle : LocalizedString(isRunning ? @"tooltip.on" : @"tooltip.off");
    if (button.alphaValue != 1.0) button.alphaValue = 1.0;
    if (![button.toolTip isEqualToString:toolTip]) button.toolTip = toolTip;
    if (![button.accessibilityLabel isEqualToString:menuTitle]) button.accessibilityLabel = menuTitle;
    // AppKit invalidates the button when its image or title changes.
}

- (void)scheduleStatusVerification {
    [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(refreshStatus) userInfo:nil repeats:NO];
}

- (BOOL)stayAwakeIsRunningOrStarting {
    if ([self runningPid] != 0) {
        return YES;
    }

    return self.startedTask.running;
}

- (void)toggleStayAwake:(id)sender {
    [self setStayAwakeRunning:![self stayAwakeIsRunningOrStarting]];
}

- (void)setStayAwakeRunning:(BOOL)shouldRun {
    BOOL isRunning = [self stayAwakeIsRunningOrStarting];
    if (shouldRun == isRunning) {
        [self applyStatusPresentationForRunning:isRunning];
        return;
    }

    if (shouldRun) {
        if ([self startStayAwakeForSeconds:0 notifying:YES]) {
            [self applyStatusPresentationForRunning:YES];
            [self scheduleStatusVerification];
        } else {
            [self refreshStatus];
        }
    } else {
        [self stopStayAwake];
        [self applyStatusPresentationForRunning:NO];
        [self scheduleStatusVerification];
    }
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

- (NSString *)applicationVersion {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
}

- (NSTextField *)aboutLabel:(NSString *)text frame:(NSRect)frame font:(NSFont *)font {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.frame = frame;
    label.font = font;
    label.alignment = NSTextAlignmentCenter;
    [self.aboutWindow.contentView addSubview:label];
    return label;
}

- (void)setUpdateStatusText:(NSString *)text {
    NSString *link = LocalizedString(@"about.website");
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    NSMutableAttributedString *status = [[NSMutableAttributedString alloc]
        initWithString:[text stringByAppendingFormat:@" %@", link] attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:11],
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
            NSParagraphStyleAttributeName: paragraph
        }];
    [status addAttributes:@{
        NSLinkAttributeName: [NSURL URLWithString:@"https://chocolate213.github.io/stay-awake/"],
        NSForegroundColorAttributeName: NSColor.linkColor,
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
    } range:NSMakeRange(text.length + 1, link.length)];
    self.updateStatus.attributedStringValue = status;
}

- (void)presentStayAwakeAboutPanel:(id)sender {
    (void)sender;
    if (!self.aboutWindow) {
        self.aboutWindow = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 270)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:NO];
        self.aboutWindow.title = LocalizedString(@"menu.about");
        self.aboutWindow.releasedWhenClosed = NO;
        self.aboutWindow.delegate = self;
        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(178, 188, 64, 64)];
        icon.image = [self applicationIcon] ?: NSApp.applicationIconImage;
        icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self.aboutWindow.contentView addSubview:icon];
        [self aboutLabel:LocalizedString(@"app.name") frame:NSMakeRect(20, 157, 380, 26)
            font:[NSFont boldSystemFontOfSize:20]];
        NSTextField *version = [self aboutLabel:[NSString stringWithFormat:LocalizedString(@"about.version"), [self applicationVersion]]
            frame:NSMakeRect(20, 133, 380, 20) font:[NSFont systemFontOfSize:12]];
        version.textColor = NSColor.secondaryLabelColor;
        [self aboutLabel:LocalizedString(@"about.credits") frame:NSMakeRect(36, 99, 348, 20)
            font:[NSFont systemFontOfSize:13]];
        self.checkUpdatesButton = [NSButton buttonWithTitle:LocalizedString(@"updates.check")
            target:self action:@selector(checkForUpdates:)];
        self.checkUpdatesButton.frame = NSMakeRect(105, 51, 210, 32);
        [self.aboutWindow.contentView addSubview:self.checkUpdatesButton];
        self.updateStatus = [self aboutLabel:@"" frame:NSMakeRect(20, 21, 380, 20)
            font:[NSFont systemFontOfSize:11]];
        self.updateStatus.selectable = YES;
        self.updateStatus.allowsEditingTextAttributes = YES;
        [self setUpdateStatusText:LocalizedString(@"updates.manual")];
        [self.aboutWindow center];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.aboutWindow makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == self.aboutWindow) {
        [self.updateSession invalidateAndCancel];
        self.updateSession = nil;
        self.checkUpdatesButton.enabled = YES;
        self.checkUpdatesButton.title = LocalizedString(@"updates.check");
        [self setUpdateStatusText:LocalizedString(@"updates.manual")];
    }
}

- (void)presentUpdateAlert:(NSAlert *)alert destination:(NSURL *)destination {
    [alert beginSheetModalForWindow:self.aboutWindow completionHandler:^(NSModalResponse response) {
        if (destination && response == NSAlertFirstButtonReturn) {
            [NSWorkspace.sharedWorkspace openURL:destination];
        }
    }];
}

- (void)showUpdateRelease:(UpdateRelease *)release failureKey:(NSString *)failureKey {
    NSComparisonResult comparison = NSOrderedSame;
    if (release && !CompareUpdateVersions(release.version, [self applicationVersion], &comparison)) {
        failureKey = @"updates.error.invalid";
        release = nil;
    }
    NSAlert *alert = [NSAlert new];
    if (!release) {
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = LocalizedString(@"updates.error.title");
        alert.informativeText = LocalizedString(failureKey ?: @"updates.error.invalid");
        [alert addButtonWithTitle:LocalizedString(@"updates.viewReleases")];
        [alert addButtonWithTitle:LocalizedString(@"updates.close")];
        [self presentUpdateAlert:alert destination:[NSURL URLWithString:@"https://github.com/chocolate213/stay-awake/releases"]];
    } else if (comparison != NSOrderedDescending) {
        alert.messageText = LocalizedString(@"updates.current.title");
        alert.informativeText = [NSString stringWithFormat:LocalizedString(@"updates.current.detail"),
            [self applicationVersion], release.version];
        [alert addButtonWithTitle:LocalizedString(@"updates.close")];
        [self presentUpdateAlert:alert destination:nil];
    } else {
        alert.messageText = [NSString stringWithFormat:LocalizedString(@"updates.available.title"), release.version];
        alert.informativeText = [NSString stringWithFormat:LocalizedString(@"updates.available.detail"), [self applicationVersion]];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 360, 140)];
        scroll.hasVerticalScroller = YES;
        scroll.borderType = NSBezelBorder;
        NSTextView *notes = [[NSTextView alloc] initWithFrame:scroll.bounds];
        notes.editable = NO;
        notes.font = [NSFont systemFontOfSize:12];
        notes.textColor = NSColor.labelColor;
        notes.backgroundColor = NSColor.textBackgroundColor;
        notes.textContainerInset = NSMakeSize(8, 8);
        notes.autoresizingMask = NSViewWidthSizable;
        notes.textContainer.widthTracksTextView = YES;
        notes.string = release.notes.length ? release.notes : LocalizedString(@"updates.notes.empty");
        scroll.documentView = notes;
        alert.accessoryView = scroll;
        [alert addButtonWithTitle:LocalizedString(@"updates.download")];
        [alert addButtonWithTitle:LocalizedString(@"updates.later")];
        [self presentUpdateAlert:alert destination:release.pageURL];
    }
}

- (NSURLSessionConfiguration *)updateSessionConfiguration {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 15;
    configuration.timeoutIntervalForResource = 30;
    return configuration;
}

- (void)checkForUpdates:(id)sender {
    (void)sender;
    if (self.updateSession) return;
    self.checkUpdatesButton.enabled = NO;
    self.checkUpdatesButton.title = LocalizedString(@"updates.checking");
    [self setUpdateStatusText:LocalizedString(@"updates.connecting")];
    NSURLSessionConfiguration *configuration = [self updateSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    self.updateSession = session;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://api.github.com/repos/chocolate213/stay-awake/releases/latest"]];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [request setValue:@"Stay-Awake-Update-Check" forHTTPHeaderField:@"User-Agent"];
    __weak StayAwakeApp *weakSelf = self;
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *failureKey = nil;
        UpdateRelease *release = [UpdateRelease releaseFromData:data response:response networkError:error failureKey:&failureKey];
        dispatch_async(dispatch_get_main_queue(), ^{
            StayAwakeApp *app = weakSelf;
            // Ignore cancelled checks, including a window closed and reopened during the request.
            if (!app || app.updateSession != session) return;
            [session finishTasksAndInvalidate];
            app.updateSession = nil;
            app.checkUpdatesButton.enabled = YES;
            app.checkUpdatesButton.title = LocalizedString(@"updates.check");
            [app setUpdateStatusText:LocalizedString(@"updates.manual")];
            [app showUpdateRelease:release failureKey:failureKey];
        });
    }] resume];
}

- (void)startPreset:(NSMenuItem *)sender {
    [self replaceSessionWithSeconds:sender.tag];
}

- (NSTimeInterval)secondsForCustomMinutes:(NSString *)text {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (value.length == 0 || value.length > 5 || [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound) return -1;
    NSInteger minutes = value.integerValue;
    return minutes >= 1 && minutes <= 10080 ? minutes * 60 : -1;
}

- (NSDate *)nextDeadlineForTime:(NSDate *)time afterDate:(NSDate *)now calendar:(NSCalendar *)calendar {
    NSDateComponents *parts = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:time];
    parts.second = 0;
    return [calendar nextDateAfterDate:now matchingComponents:parts options:NSCalendarMatchNextTime | NSCalendarMatchFirst];
}

- (void)updateUntilPreview:(id)sender {
    (void)sender;
    NSDate *now = NSDate.date;
    NSDate *deadline = [self nextDeadlineForTime:self.untilPicker.dateValue afterDate:now calendar:NSCalendar.currentCalendar];
    NSString *day = LocalizedString([NSCalendar.currentCalendar isDate:deadline inSameDayAsDate:now] ? @"until.today" : @"until.tomorrow");
    NSString *time = [NSDateFormatter localizedStringFromDate:deadline dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
    self.untilPreview.stringValue = [NSString stringWithFormat:LocalizedString(@"until.preview"), day, time, [self countdownForSeconds:[deadline timeIntervalSinceDate:now]]];
    NSDateComponents *parts = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:self.untilPicker.dateValue];
    for (RoundedTimePresetButton *button in self.untilPresets) {
        BOOL selected = parts.minute == 0 && parts.hour == button.tag;
        if (button.presetSelected != selected) {
            button.presetSelected = selected;
            button.needsDisplay = YES;
        }
    }
}

- (void)selectUntilPreset:(NSButton *)sender {
    [self.untilPicker.window makeFirstResponder:nil];
    self.untilPicker.dateValue = [NSCalendar.currentCalendar dateBySettingHour:sender.tag minute:0 second:0 ofDate:NSDate.date options:0];
    [self updateUntilPreview:nil];
}

- (NSView *)timeSelectionViewWithHelp:(NSString *)help height:(CGFloat)height {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, height)];
    NSTextField *label = [NSTextField wrappingLabelWithString:help];
    label.frame = NSMakeRect(0, height - 44, 340, 44);
    [view addSubview:label];
    return view;
}

- (void)startUntil:(id)sender {
    (void)sender;
    NSAlert *alert = [NSAlert new];
    alert.messageText = LocalizedString(@"until.title");

    [alert addButtonWithTitle:LocalizedString(@"duration.start")];
    [alert addButtonWithTitle:LocalizedString(@"duration.cancel")];
    NSView *view = [self timeSelectionViewWithHelp:LocalizedString(@"until.help") height:218];
    self.untilPicker = [[ScrollableTimePicker alloc] initWithFrame:NSMakeRect(0, 52, 180, 28)];
    self.untilPicker.datePickerStyle = NSDatePickerStyleTextField;
    self.untilPicker.font = [NSFont monospacedDigitSystemFontOfSize:44 weight:NSFontWeightLight];
    self.untilPicker.bezeled = NO;
    self.untilPicker.bordered = NO;
    self.untilPicker.drawsBackground = NO;
    self.untilPicker.datePickerElements = NSDatePickerElementFlagHourMinute;
    self.untilPicker.dateValue = [NSDate dateWithTimeIntervalSinceNow:3600];
    [self.untilPicker sizeToFit];
    [self.untilPicker setFrameOrigin:NSMakePoint((340 - self.untilPicker.frame.size.width) / 2, 110)];
    self.untilPicker.accessibilityLabel = LocalizedString(@"until.title");
    self.untilPicker.target = self;
    self.untilPicker.action = @selector(updateUntilPreview:);
    [view addSubview:self.untilPicker];
    NSMutableArray<RoundedTimePresetButton *> *presets = [NSMutableArray array];
    for (NSInteger index = 0; index < 4; index++) {
        NSString *title = [NSString stringWithFormat:@"%ld:00", (long)(18 + index)];
        RoundedTimePresetButton *button = [[RoundedTimePresetButton alloc] initWithFrame:NSMakeRect(6 + index * 84, 64, 76, 30)];
        button.title = title;
        button.bordered = NO;
        button.buttonType = NSButtonTypeMomentaryChange;
        button.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium];
        button.presetSelected = NO;
        button.tag = 18 + index;
        button.target = self;
        button.action = @selector(selectUntilPreset:);
        button.accessibilityLabel = [NSString stringWithFormat:LocalizedString(@"until.preset.accessibility"), title];
        [presets addObject:button];
        [view addSubview:button];
    }
    self.untilPresets = presets;
    self.untilPreview = [NSTextField wrappingLabelWithString:@""];
    self.untilPreview.frame = NSMakeRect(0, 0, 340, 44);
    self.untilPreview.textColor = NSColor.secondaryLabelColor;
    self.untilPreview.alignment = NSTextAlignmentCenter;
    [view addSubview:self.untilPreview];
    alert.accessoryView = view;
    [self updateUntilPreview:nil];
    NSTimer *timer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(updateUntilPreview:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSModalPanelRunLoopMode];
    [NSApp activateIgnoringOtherApps:YES];
    alert.window.initialFirstResponder = self.untilPicker;
    NSModalResponse response = [alert runModal];
    [alert.window makeFirstResponder:nil];
    [timer invalidate];
    if (response == NSAlertFirstButtonReturn) {
        NSDate *now = NSDate.date;
        NSDate *deadline = [self nextDeadlineForTime:self.untilPicker.dateValue afterDate:now calendar:NSCalendar.currentCalendar];
        [self replaceSessionWithSeconds:[deadline timeIntervalSinceDate:now]];
    }
    self.untilPicker = nil;
    self.untilPresets = nil;
    self.untilPreview = nil;
}

- (void)durationStepperChanged:(NSStepper *)sender {
    NSTextField *field = [sender.superview viewWithTag:sender.tag - 10];
    NSString *candidate = [NSString stringWithFormat:@"%ld", sender.integerValue];
    if ([field.formatter isPartialStringValid:candidate newEditingString:NULL errorDescription:NULL]) {
        field.stringValue = candidate;
    } else {
        sender.integerValue = field.integerValue;
    }
}

- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *field = notification.object;
    NSStepper *stepper = [field.superview viewWithTag:field.tag + 10];
    if ([stepper isKindOfClass:NSStepper.class]) stepper.integerValue = field.integerValue;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = notification.object;
    if (field.stringValue.length == 0) {
        NSTextField *other = [field.superview viewWithTag:field.tag == 1 ? 2 : 1];
        field.integerValue = other.integerValue == 0 ? 1 : 0;
        [self controlTextDidChange:notification];
    }
}

- (NSTextField *)addDurationFieldToView:(NSView *)view x:(CGFloat)x tag:(NSInteger)tag label:(NSString *)label maximum:(NSInteger)maximum value:(NSInteger)value {
    NSTextField *caption = [NSTextField labelWithString:label];
    caption.frame = NSMakeRect(x, 118, 110, 20);
    caption.alignment = NSTextAlignmentCenter;
    caption.textColor = NSColor.secondaryLabelColor;
    [view addSubview:caption];
    NSTextField *field = [[ScrollableDurationField alloc] initWithFrame:NSMakeRect(x, 62, 110, 58)];
    field.font = [NSFont monospacedDigitSystemFontOfSize:44 weight:NSFontWeightLight];
    field.alignment = NSTextAlignmentCenter;
    field.bezeled = NO;
    field.bordered = NO;
    field.drawsBackground = NO;
    field.tag = tag;
    field.integerValue = value;
    field.accessibilityLabel = label;
    field.delegate = self;
    DurationFormatter *formatter = [DurationFormatter new];
    formatter.field = field;
    field.formatter = formatter;
    [view addSubview:field];
    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(x + 112, 79, 20, 27)];
    stepper.minValue = 0;
    stepper.maxValue = maximum;
    stepper.increment = 1;
    stepper.valueWraps = NO;
    stepper.integerValue = value;
    stepper.tag = tag + 10;
    stepper.target = self;
    stepper.action = @selector(durationStepperChanged:);
    stepper.accessibilityLabel = label;
    [view addSubview:stepper];
    return field;
}

- (NSTimeInterval)secondsForDurationHours:(NSString *)hours minutes:(NSString *)minutes {
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
    for (NSString *value in @[hours, minutes]) {
        if (value.length == 0 || value.length > 3 || [value rangeOfCharacterFromSet:invalid].location != NSNotFound) return -1;
    }
    if (hours.integerValue > 168 || minutes.integerValue > 59) return -1;
    return [self secondsForCustomMinutes:[NSString stringWithFormat:@"%ld", hours.integerValue * 60 + minutes.integerValue]];
}

- (void)startCustom:(id)sender {
    (void)sender;
    NSAlert *alert = [NSAlert new];
    alert.messageText = LocalizedString(@"duration.custom");

    [alert addButtonWithTitle:LocalizedString(@"duration.start")];
    [alert addButtonWithTitle:LocalizedString(@"duration.cancel")];
    NSView *view = [self timeSelectionViewWithHelp:LocalizedString(@"duration.picker.help") height:194];
    NSTextField *hours = [self addDurationFieldToView:view x:20 tag:1 label:LocalizedString(@"duration.hours.label") maximum:168 value:1];
    NSTextField *minutes = [self addDurationFieldToView:view x:190 tag:2 label:LocalizedString(@"duration.minutes.label") maximum:59 value:30];
    alert.accessoryView = view;
    [NSApp activateIgnoringOtherApps:YES];
    alert.window.initialFirstResponder = hours;
    while ([alert runModal] == NSAlertFirstButtonReturn) {
        [alert.window makeFirstResponder:nil];
        NSTimeInterval seconds = [self secondsForDurationHours:hours.stringValue minutes:minutes.stringValue];
        if (seconds > 0) {
            [self replaceSessionWithSeconds:seconds];
            return;
        }
        alert.informativeText = LocalizedString(@"duration.picker.invalid");
    }
}

- (void)replaceSessionWithSeconds:(NSTimeInterval)seconds {
    // Launch the replacement before stopping the previous process.
    [self startStayAwakeForSeconds:seconds notifying:NO];
    [self refreshStatus];
    [self scheduleStatusVerification];
}

- (void)extendSession:(id)sender {
    (void)sender;
    NSDate *deadline = [self activeDeadline];
    if (deadline && deadline.timeIntervalSinceNow > 0) {
        [self replaceSessionWithSeconds:ceil(deadline.timeIntervalSinceNow) + 1800];
    } else {
        [self refreshStatus];
    }
}

- (BOOL)startStayAwakeForSeconds:(NSTimeInterval)seconds notifying:(BOOL)notify {

    NSError *error = nil;
    if (![self installHelperIfNeededWithError:&error]) {
        [self showAlert:LocalizedString(@"alert.installHelper.title") detail:error.localizedDescription];
        return NO;
    }

    NSURL *helperURL = [self installedHelperURL];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:helperURL.path]) {
        [self showAlert:LocalizedString(@"alert.missingScript.title") detail:helperURL.path];
        return NO;
    }

    [NSFileManager.defaultManager createDirectoryAtURL:[self stateDirectory] withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        [self showAlert:LocalizedString(@"alert.stateDir.title") detail:error.localizedDescription];
        return NO;
    }

    [NSFileManager.defaultManager createFileAtPath:[self logFile].path contents:nil attributes:nil];
    NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:[self logFile].path];
    [logHandle seekToEndOfFile];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = helperURL;
    NSString *watchPid = [NSString stringWithFormat:@"%d", NSProcessInfo.processInfo.processIdentifier];
    NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[@"-q", @"--watch-pid", watchPid]];
    if (seconds > 0) [arguments addObjectsFromArray:@[@"--time", [NSString stringWithFormat:@"%.0f", ceil(seconds)]]];
    task.arguments = arguments;
    task.currentDirectoryURL = [helperURL URLByDeletingLastPathComponent];
    task.standardOutput = logHandle;
    task.standardError = logHandle;

    pid_t previousPid = [self runningPid];
    NSTask *previousTask = self.startedTask;
    NSData *previousSession = [NSData dataWithContentsOfURL:[self sessionFile]];
    @try {
        [task launch];
        NSDate *deadline = seconds > 0 ? [NSDate dateWithTimeIntervalSinceNow:ceil(seconds)] : nil;
        NSMutableDictionary *session = [NSMutableDictionary dictionaryWithObject:@(task.processIdentifier) forKey:@"pid"];
        if (deadline) session[@"deadline"] = deadline;
        NSData *sessionData = [NSPropertyListSerialization dataWithPropertyList:session format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if (!sessionData || ![sessionData writeToURL:[self sessionFile] options:NSDataWritingAtomic error:&error]) {
            [task terminate];
            [self showAlert:LocalizedString(@"alert.pidFile.title") detail:error.localizedDescription];
            return NO;
        }
        NSString *pidText = [NSString stringWithFormat:@"%d\n", task.processIdentifier];
        [pidText writeToURL:[self pidFile] atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            [task terminate];
            if (previousSession) [previousSession writeToURL:[self sessionFile] atomically:YES];
            else [NSFileManager.defaultManager removeItemAtURL:[self sessionFile] error:nil];
            [self showAlert:LocalizedString(@"alert.pidFile.title") detail:error.localizedDescription];
            return NO;
        }
        self.startedTask = task;
        self.startedDeadline = deadline;
        if (previousTask.running) [previousTask terminate];
        else if (previousPid > 0) kill(previousPid, SIGTERM);
        __weak StayAwakeApp *weakSelf = self;
        task.terminationHandler = ^(NSTask *finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                StayAwakeApp *owner = weakSelf;
                if (owner.startedTask == finished) {
                    owner.startedTask = nil;
                    owner.startedDeadline = nil;
                    [owner refreshStatus];
                }
            });
        };
        if (notify) [self showNotification:LocalizedString(@"notification.on")];
        return YES;
    } @catch (NSException *exception) {
        [self showAlert:LocalizedString(@"alert.startFailed.title") detail:exception.reason ?: LocalizedString(@"alert.unknownError")];
        return NO;
    }
}

- (void)stopStayAwake {
    [self stopStayAwakeNotifying:YES];
}

- (void)stopStayAwakeNotifying:(BOOL)notify {
    pid_t pid = [self runningPid];
    BOOL wasRunning = pid > 0 || self.startedTask.running;
    if (self.startedTask.running) {
        [self.startedTask terminate];
        if (pid == self.startedTask.processIdentifier) pid = 0;
    }
    if (pid != 0) {
        kill(pid, SIGTERM);
    }
    self.startedTask = nil;
    self.startedDeadline = nil;
    [NSFileManager.defaultManager removeItemAtURL:[self pidFile] error:nil];
    [NSFileManager.defaultManager removeItemAtURL:[self sessionFile] error:nil];
    if (notify && wasRunning) [self showNotification:LocalizedString(@"notification.off")];
}

- (pid_t)runningPid {
    if ([self pidFilePredatesCurrentBoot]) {
        [NSFileManager.defaultManager removeItemAtURL:[self pidFile] error:nil];
        [NSFileManager.defaultManager removeItemAtURL:[self sessionFile] error:nil];
        return 0;
    }

    NSString *pidText = [NSString stringWithContentsOfURL:[self pidFile] encoding:NSUTF8StringEncoding error:nil];
    pid_t pid = (pid_t)[pidText integerValue];
    if (pid <= 0 || kill(pid, 0) != 0) {
        [NSFileManager.defaultManager removeItemAtURL:[self pidFile] error:nil];
        [NSFileManager.defaultManager removeItemAtURL:[self sessionFile] error:nil];
        return 0;
    }

    // The helper shell briefly exists before exec replaces it with caffeinate.
    if (self.startedTask.running && self.startedTask.processIdentifier == pid) return pid;
    NSString *executableName = [self executableNameForPid:pid];
    return [executableName isEqualToString:@"caffeinate"] ? pid : 0;
}

- (BOOL)pidFilePredatesCurrentBoot {
    NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:[self pidFile].path error:nil];
    NSDate *modificationDate = attributes[NSFileModificationDate];
    if (!modificationDate) {
        return NO;
    }

    NSDate *bootDate = [NSDate dateWithTimeIntervalSinceNow:-NSProcessInfo.processInfo.systemUptime];
    return [modificationDate compare:bootDate] == NSOrderedAscending;
}

- (NSString *)executableNameForPid:(pid_t)pid {
    char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int length = proc_pidpath(pid, pathBuffer, sizeof(pathBuffer));
    if (length <= 0) {
        return @"";
    }

    NSString *path = [[NSString alloc] initWithBytes:pathBuffer length:(NSUInteger)length encoding:NSUTF8StringEncoding] ?: @"";
    return path.lastPathComponent;
}

- (BOOL)installHelperIfNeededWithError:(NSError **)error {
    NSURL *sourceURL = [self bundledHelperURL];
    if (!sourceURL) {
        if (error) {
            *error = [self applicationErrorWithDescription:LocalizedString(@"alert.bundledHelperMissing.detail")];
        }
        return NO;
    }

    NSArray<NSURL *> *directories = @[[self applicationSupportDirectory], [self scriptsDirectory], [self stateDirectory], [self logsDirectory]];
    for (NSURL *directory in directories) {
        if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    NSURL *destinationURL = [self installedHelperURL];
    NSData *sourceData = [NSData dataWithContentsOfURL:sourceURL options:0 error:error];
    if (!sourceData) {
        return NO;
    }

    NSData *existingData = [NSData dataWithContentsOfURL:destinationURL options:0 error:nil];
    if (![sourceData isEqualToData:existingData]) {
        [NSFileManager.defaultManager removeItemAtURL:destinationURL error:nil];
        if (![NSFileManager.defaultManager copyItemAtURL:sourceURL toURL:destinationURL error:error]) {
            return NO;
        }
    }

    NSDictionary<NSFileAttributeKey, id> *attributes = @{NSFilePosixPermissions: @0755};
    return [NSFileManager.defaultManager setAttributes:attributes ofItemAtPath:destinationURL.path error:error];
}

- (NSError *)applicationErrorWithDescription:(NSString *)description {
    return [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier ?: @"local.stay-awake.menu"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @""}];
}

- (void)requestNotificationPermission {
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound;
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError *error) {
        (void)granted;
        (void)error;
    }];
}

- (void)showNotification:(NSString *)message {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = LocalizedString(@"app.name");
    content.body = message;

    NSString *identifier = [NSString stringWithFormat:@"local.stay-awake.%@", NSUUID.UUID.UUIDString];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:nil];
}

- (void)showAlert:(NSString *)message detail:(NSString *)detail {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = detail;
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        StayAwakeApp *delegate = [[StayAwakeApp alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
