// Exercise the production session lifecycle with real, short-lived caffeinate tasks.
#define main StayAwakeApplicationMain
#import "../StayAwakeMenu/main.m"
#undef main

// Observe writes to the status button without relying on AppKit's redraw coalescing.
@interface StatusButtonProbe : NSObject
@property(nonatomic, strong) NSImage *image;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *toolTip;
@property(nonatomic, copy) NSString *accessibilityLabel;
@property(nonatomic) CGFloat alphaValue;
@property(nonatomic) NSUInteger imageWrites;
@property(nonatomic) NSUInteger titleWrites;
@property(nonatomic) NSUInteger tooltipWrites;
@property(nonatomic) NSUInteger accessibilityWrites;
@property(nonatomic) NSUInteger displayRequests;
@end
@implementation StatusButtonProbe
- (void)setImage:(NSImage *)image { _image = image; self.imageWrites++; }
- (void)setTitle:(NSString *)title { _title = [title copy]; self.titleWrites++; }
- (void)setToolTip:(NSString *)toolTip { _toolTip = [toolTip copy]; self.tooltipWrites++; }
- (void)setAccessibilityLabel:(NSString *)label { _accessibilityLabel = [label copy]; self.accessibilityWrites++; }
- (void)setNeedsDisplay:(BOOL)needed { if (needed) self.displayRequests++; }
@end
@interface StatusItemProbe : NSObject
@property(nonatomic, strong) StatusButtonProbe *button;
@end
@implementation StatusItemProbe
@end
@interface PresentationTestApp : StayAwakeApp
@property(nonatomic, strong) NSDate *testDeadline;
@end
@implementation PresentationTestApp
- (NSDate *)activeDeadline { return self.testDeadline; }
@end

// Exercise the real async update path without depending on GitHub availability.
static BOOL HoldUpdateResponse;
static NSInteger UpdateHTTPStatus = 200;
static NSError *UpdateNetworkError;
static NSString *UpdateTag = @"v1.2.0";
@interface TestUpdateProtocol : NSURLProtocol
@end
@implementation TestUpdateProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [request.URL.absoluteString isEqualToString:@"https://api.github.com/repos/chocolate213/stay-awake/releases/latest"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    if (HoldUpdateResponse) return;
    if (UpdateNetworkError) {
        [self.client URLProtocol:self didFailWithError:UpdateNetworkError];
        return;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
        statusCode:UpdateHTTPStatus HTTPVersion:@"HTTP/1.1" headerFields:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"tag_name": UpdateTag,
        @"draft": @NO, @"prerelease": @NO, @"body": @"Test release notes"} options:0 error:NULL];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface TestScrollEvent : NSEvent
@property(nonatomic) CGFloat testDelta;
@property(nonatomic) BOOL precise;
@property(nonatomic) NSEventPhase testMomentum;
@end
@implementation TestScrollEvent
- (CGFloat)scrollingDeltaY { return self.testDelta; }
- (BOOL)hasPreciseScrollingDeltas { return self.precise; }
- (NSEventPhase)phase { return NSEventPhaseNone; }
- (NSEventPhase)momentumPhase { return self.testMomentum; }
@end

@interface TestApp : StayAwakeApp
@property(nonatomic, strong) NSURL *testRoot;
@property(nonatomic, strong) NSURL *helperSource;
@property(nonatomic) NSUInteger notificationCount;
@property(nonatomic) NSUInteger alertCount;
@property(nonatomic, strong) NSAlert *updateAlert;
@property(nonatomic, strong) NSURL *updateDestination;
@end
@implementation TestApp
- (NSURL *)applicationSupportDirectory { return self.testRoot; }
- (NSURL *)bundledHelperURL { return self.helperSource; }
- (NSString *)applicationVersion { return @"1.1.1"; }
- (NSURLSessionConfiguration *)updateSessionConfiguration {
    NSURLSessionConfiguration *configuration = [super updateSessionConfiguration];
    configuration.protocolClasses = @[TestUpdateProtocol.class];
    return configuration;
}
- (void)presentUpdateAlert:(NSAlert *)alert destination:(NSURL *)destination {
    self.updateAlert = alert;
    self.updateDestination = destination;
}
- (void)showNotification:(NSString *)message { (void)message; self.notificationCount++; }
- (void)showAlert:(NSString *)message detail:(NSString *)detail {
    (void)message; (void)detail; self.alertCount++;
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Check(argc == 3, @"helper source and locale arguments");
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"AppleLanguages": @[@(argv[2])]} forName:NSArgumentDomain];
        [NSApplication sharedApplication];
        Check(![LocalizedString(@"countdown.minutes") isEqualToString:@"countdown.minutes"], @"bundled countdown localization resolves");
        TestApp *app = [TestApp new];
        app.testRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        app.helperSource = [NSURL fileURLWithPath:@(argv[1])];
        @try {
            PresentationTestApp *presentation = [PresentationTestApp new];
            StatusItemProbe *item = [StatusItemProbe new];
            StatusButtonProbe *button = [StatusButtonProbe new];
            item.button = button;
            presentation.statusItem = (NSStatusItem *)item;
            presentation.statusMenuItem = [NSMenuItem new];
            presentation.toggleMenuItem = [NSMenuItem new];
            presentation.extendMenuItem = [NSMenuItem new];
            NSImage *offImage = [presentation statusBarImageForRunning:NO];
            NSImage *onImage = [presentation statusBarImageForRunning:YES];
            Check(offImage && onImage && offImage != onImage && offImage.template && onImage.template,
                @"distinct On/Off template images");
            Check([presentation statusBarImageForRunning:NO] == offImage &&
                [presentation statusBarImageForRunning:YES] == onImage, @"reuse configured status symbols");
            [presentation applyStatusPresentationForRunning:NO];
            for (NSUInteger index = 0; index < 12; index++) [presentation applyStatusPresentationForRunning:NO];
            Check(button.imageWrites == 1 && button.titleWrites == 1 && button.tooltipWrites == 1 &&
                button.accessibilityWrites == 1, @"unchanged Off display is not reassigned on polling");
            [presentation applyStatusPresentationForRunning:YES];
            [presentation applyStatusPresentationForRunning:YES];
            Check(button.image == onImage && button.imageWrites == 2 && button.titleWrites == 2,
                @"state transition switches image and title once");
            presentation.testDeadline = [NSDate dateWithTimeIntervalSinceNow:128];
            [presentation applyStatusPresentationForRunning:YES];
            for (NSUInteger index = 0; index < 12; index++) [presentation applyStatusPresentationForRunning:YES];
            Check(button.imageWrites == 2 && button.titleWrites == 3 && presentation.extendMenuItem.enabled,
                @"unchanged countdown keeps its icon and title while enabling extension");
            presentation.testDeadline = [NSDate dateWithTimeIntervalSinceNow:58];
            [presentation applyStatusPresentationForRunning:YES];
            Check(button.imageWrites == 2 && button.titleWrites == 4 &&
                [button.title containsString:LocalizedString(@"countdown.lessThanMinute")], @"countdown change updates text without replacing icon");
            Check([button.accessibilityLabel isEqualToString:presentation.statusMenuItem.title] &&
                [button.toolTip isEqualToString:presentation.statusMenuItem.title], @"accessibility and tooltip track countdown");
            presentation.testDeadline = nil;
            [presentation applyStatusPresentationForRunning:NO];
            Check(button.image == offImage && button.imageWrites == 3 && !presentation.extendMenuItem.enabled,
                @"stop restores cached Off symbol and disables extension");
            Check(button.displayRequests == 0, @"no forced status button redraws");
            [app presentStayAwakeAboutPanel:nil];
            NSWindow *about = app.aboutWindow;
            [app presentStayAwakeAboutPanel:nil];
            Check(app.aboutWindow == about && !app.updateSession, @"About reuses its window and does not check automatically");
            [app checkForUpdates:nil];
            NSURLSession *firstCheck = app.updateSession;
            [app checkForUpdates:nil];
            Check(firstCheck && app.updateSession == firstCheck && !app.checkUpdatesButton.enabled, @"duplicate checks suppressed");
            Pump(0.5);
            Check(!app.updateSession && app.checkUpdatesButton.enabled, @"successful check resets loading state");
            Check(app.updateDestination && app.updateAlert.accessoryView &&
                [app.updateAlert.messageText containsString:@"1.2.0"], @"new release offers download page and notes");
            for (NSString *tag in @[@"v1.1.1", @"v1.0.4"]) {
                UpdateTag = tag;
                [app checkForUpdates:nil]; Pump(0.5);
                Check(!app.updateDestination && !app.updateAlert.accessoryView &&
                    [app.updateAlert.messageText isEqualToString:LocalizedString(@"updates.current.title")], @"same or older release offers no downgrade");
            }
            UpdateHTTPStatus = 429;
            [app checkForUpdates:nil]; Pump(0.5);
            Check([app.updateAlert.informativeText isEqualToString:LocalizedString(@"updates.error.rateLimit")] &&
                app.updateDestination && app.checkUpdatesButton.enabled, @"rate limit recovers and offers releases page");
            UpdateHTTPStatus = 200;
            UpdateNetworkError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
            [app checkForUpdates:nil]; Pump(0.5);
            Check([app.updateAlert.informativeText isEqualToString:LocalizedString(@"updates.error.network")] &&
                app.checkUpdatesButton.enabled, @"offline check shows actionable localized error");
            UpdateNetworkError = nil;
            HoldUpdateResponse = YES;
            app.updateAlert = nil;
            [app checkForUpdates:nil];
            [app.aboutWindow close]; Pump(0.1);
            Check(!app.updateSession && !app.updateAlert && app.checkUpdatesButton.enabled, @"closing About cancels check without a late alert");
            HoldUpdateResponse = NO;
            UpdateTag = @"v1.2.0";
            [app presentStayAwakeAboutPanel:nil];
            [app checkForUpdates:nil]; Pump(0.5);
            Check(app.updateDestination && app.checkUpdatesButton.enabled, @"reopened About can retry");
            [app.aboutWindow close];
            NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
            calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            NSDateComponents *base = [NSDateComponents new];
            base.year = 2026; base.month = 9; base.day = 18; base.hour = 23;
            NSDate *now = [calendar dateFromComponents:base];
            NSDate *fourAM = [now dateByAddingTimeInterval:-19 * 3600];
            Check([[app nextDeadlineForTime:fourAM afterDate:now calendar:calendar] timeIntervalSinceDate:now] == 5 * 3600, @"23:00 to 04:00 means tomorrow");
            Check([[app nextDeadlineForTime:now afterDate:now calendar:calendar] timeIntervalSinceDate:now] == 24 * 3600, @"current minute means tomorrow");
            NSDate *earlier = [now dateByAddingTimeInterval:-3600];
            Check([[app nextDeadlineForTime:now afterDate:earlier calendar:calendar] timeIntervalSinceDate:earlier] == 3600, @"future clock time means today");
            NSView *durationView = [NSView new];
            NSTextField *hoursField = [app addDurationFieldToView:durationView x:0 tag:1 label:@"Hours" maximum:168 value:1];
            NSTextField *minutesField = [app addDurationFieldToView:durationView x:160 tag:2 label:@"Minutes" maximum:59 value:30];
            for (NSString *invalid in @[@"-1", @"1.5", @"a", @"60", @"999", @" 2"]) {
                Check(![minutesField.formatter isPartialStringValid:invalid newEditingString:NULL errorDescription:NULL], @"reject invalid typing and paste before accepting edits");
            }
            Check([minutesField.formatter isPartialStringValid:@"" newEditingString:NULL errorDescription:NULL], @"allow deletion while editing");
            Check(![hoursField.formatter isPartialStringValid:@"168" newEditingString:NULL errorDescription:NULL], @"reject combined duration over seven days during editing");
            minutesField.stringValue = @"0";
            Check([hoursField.formatter isPartialStringValid:@"168" newEditingString:NULL errorDescription:NULL], @"allow exact seven day boundary");
            Check(![hoursField.formatter isPartialStringValid:@"0" newEditingString:NULL errorDescription:NULL], @"reject explicit zero total");
            hoursField.stringValue = @"";
            [app controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:hoursField]];
            Check(hoursField.integerValue == 1, @"normalize empty field to a valid duration on focus loss");
            TestScrollEvent *scroll = [TestScrollEvent new];
            scroll.testDelta = -1;
            [(ScrollableDurationField *)hoursField scrollWheel:scroll];
            Check(hoursField.integerValue == 1, @"scroll cannot reduce total duration to zero");
            minutesField.stringValue = @"59";
            scroll.testDelta = 1;
            [(ScrollableDurationField *)minutesField scrollWheel:scroll];
            Check(minutesField.integerValue == 59, @"scroll respects minute upper bound");
            hoursField.stringValue = @"167";
            [(ScrollableDurationField *)hoursField scrollWheel:scroll];
            Check(hoursField.integerValue == 167, @"scroll respects combined seven day limit");
            minutesField.stringValue = @"0";
            [(ScrollableDurationField *)hoursField scrollWheel:scroll];
            Check(hoursField.integerValue == 168, @"scroll reaches exact seven day limit");
            TimeScrollAccumulator *accumulator = [TimeScrollAccumulator new];
            scroll.precise = YES; scroll.testDelta = 6;
            Check([accumulator stepsForEvent:scroll] == 0, @"small trackpad movement accumulates");
            Check([accumulator stepsForEvent:scroll] == 1, @"trackpad threshold yields one step");
            scroll.testMomentum = NSEventPhaseChanged; scroll.testDelta = 120;
            Check([accumulator stepsForEvent:scroll] == 0, @"ignore inertial scrolling");

            Check([app secondsForDurationHours:@"1" minutes:@"30"] == 5400, @"duration hours plus minutes");
            Check([app secondsForDurationHours:@"0" minutes:@"1"] == 60, @"duration minimum");
            Check([app secondsForDurationHours:@"168" minutes:@"0"] == 604800, @"duration maximum");
            Check([app secondsForDurationHours:@"168" minutes:@"1"] < 0, @"duration over maximum rejected");
            Check([app secondsForDurationHours:@"0" minutes:@"0"] < 0, @"zero duration rejected");
            Check([app secondsForDurationHours:@"1" minutes:@"60"] < 0, @"invalid minute component rejected");
            Check([app secondsForDurationHours:@"1.5" minutes:@"0"] < 0, @"fractional hours rejected");
            [app configureStatusItem];
            Check(app.toggleMenuItem.state == NSControlStateValueOff, @"inactive toggle action has no checkmark");
            Check(app.durationMenuItem.submenu.numberOfItems == 11, @"preset and custom actions present");
            NSArray<NSString *> *expectedTitles = [@(argv[2]) isEqualToString:@"en"] ?
                @[@"15 minutes", @"30 minutes", @"1 hour", @"2 hours", @"3 hours", @"4 hours", @"5 hours", @"8 hours"] :
                @[@"15 分钟", @"30 分钟", @"1 小时", @"2 小时", @"3 小时", @"4 小时", @"5 小时", @"8 小时"];
            for (NSUInteger index = 0; index < expectedTitles.count; index++) {
                Check([[app.durationMenuItem.submenu itemAtIndex:index].title isEqualToString:expectedTitles[index]], @"preset labels use spaced units and correct plural forms");
            }
            for (NSUInteger index = 4; index <= 7; index++) {
                NSMenuItem *preset = [app.durationMenuItem.submenu itemAtIndex:index];
                NSInteger hours = [@[@3, @4, @5, @8][index - 4] integerValue];
                Check(preset.tag == hours * 3600, @"long presets use seconds");
                [app startPreset:preset];
                NSTimeInterval remaining = [app activeDeadline].timeIntervalSinceNow;
                Check(remaining > hours * 3600 - 5 && remaining <= hours * 3600, @"long preset starts correct deadline");
                [app stopStayAwakeNotifying:NO];
            }
            [app refreshStatus];
            Check(!app.extendMenuItem.enabled && [app.statusItem.button.title isEqualToString:[@" " stringByAppendingString:LocalizedString(@"countdown.off")]], @"off state shows Off and disables extension");
            Check([app secondsForCustomMinutes:@"90"] == 5400, @"custom minutes");
            Check([app secondsForCustomMinutes:@" 1 "] == 60, @"custom lower bound");
            Check([app secondsForCustomMinutes:@"10080"] == 604800, @"custom upper bound");
            for (NSString *invalid in @[@"", @"0", @"-1", @"1.5", @"1h", @"10081", @"9999999999999999999"]) {
                Check([app secondsForCustomMinutes:invalid] < 0, @"reject invalid duration");
            }
            Check([[app countdownForSeconds:59] isEqualToString:LocalizedString(@"countdown.lessThanMinute")], @"sub-minute display");
            Check([[app countdownForSeconds:61] isEqualToString:[NSString stringWithFormat:LocalizedString(@"countdown.minutes"), (NSInteger)2]], @"round remaining minutes up");
            Check([[app countdownForSeconds:3600] isEqualToString:[NSString stringWithFormat:LocalizedString(@"countdown.hoursMinutes"), (NSInteger)1, (NSInteger)0]], @"hour display");

            Check([app startStayAwakeForSeconds:3 notifying:NO], @"start timed session");
            NSTask *first = app.startedTask;
            Check(app.toggleMenuItem.state == NSControlStateValueOff, @"active toggle action has no checkmark");
            [app refreshStatus];
            Check(app.statusItem.button.title.length > 0 && app.extendMenuItem.enabled, @"timed session displays countdown and enables extension");
            Check([app activeDeadline].timeIntervalSinceNow > 1, @"deadline available immediately");
            NSDate *deadlineBeforeCheck = [app activeDeadline];
            [app presentStayAwakeAboutPanel:nil];
            [app checkForUpdates:nil]; Pump(0.5);
            Check(app.startedTask == first && first.running && [[app activeDeadline] isEqualToDate:deadlineBeforeCheck],
                @"checking updates preserves the active session and deadline");
            [app.aboutWindow close];
            NSDate *oldDeadline = [app activeDeadline];
            [app extendSession:nil];
            NSTask *extended = app.startedTask;
            Pump(0.25);
            Check(!first.running && extended.running, @"extension replaces and stops old process");
            Check([[app activeDeadline] timeIntervalSinceDate:oldDeadline] >= 1800, @"extension adds to remaining time");
            Check([[app activeDeadline] timeIntervalSinceDate:oldDeadline] < 1802, @"extension does not reset elapsed time");
            [app stopStayAwakeNotifying:NO];
            Pump(0.1);
            Check(!extended.running && ![app stayAwakeIsRunningOrStarting] && ![app activeDeadline], @"manual stop clears process and deadline");

            Check([app startStayAwakeForSeconds:1 notifying:NO], @"start expiring session");
            NSTask *expiring = app.startedTask;
            Pump(1.5);
            [app refreshStatus];
            Check(!expiring.running && ![app stayAwakeIsRunningOrStarting], @"real caffeinate timeout ends session");
            Check(app.notificationCount == 0, @"expiration is silent");
            Check([app.statusItem.button.title isEqualToString:[@" " stringByAppendingString:LocalizedString(@"countdown.off")]] && !app.extendMenuItem.enabled, @"expiration shows Off and disables extension");
            Check(![NSFileManager.defaultManager fileExistsAtPath:app.sessionFile.path], @"expiration cleans session metadata");

            Check([app startStayAwakeForSeconds:30 notifying:NO], @"start wake reconciliation session");
            app.startedDeadline = [NSDate dateWithTimeIntervalSinceNow:-1];
            NSTask *overdue = app.startedTask;
            [app workspaceDidWake:nil];
            Pump(0.1);
            Check(!overdue.running && ![app activeDeadline], @"wake after deadline ends session");

            Check([app startStayAwakeForSeconds:0 notifying:NO], @"start indefinite session");
            NSTask *indefinite = app.startedTask;
            [app refreshStatus];
            Check(![app activeDeadline] && [app.statusItem.button.title isEqualToString:[@" " stringByAppendingString:LocalizedString(@"countdown.indefinite")]] && !app.extendMenuItem.enabled, @"indefinite shows its label and disables extension");
            [app extendSession:nil];
            Check(app.startedTask == indefinite, @"indefinite cannot be extended");

            // A metadata write failure must leave the existing session alive.
            [NSFileManager.defaultManager removeItemAtURL:[app sessionFile] error:nil];
            [NSFileManager.defaultManager createDirectoryAtURL:[app sessionFile] withIntermediateDirectories:NO attributes:nil error:nil];
            Check(![app startStayAwakeForSeconds:60 notifying:NO], @"metadata write failure is reported");
            Check(indefinite.running && app.startedTask == indefinite, @"failed replacement preserves old session");
            [NSFileManager.defaultManager removeItemAtURL:[app sessionFile] error:nil];
            [app stopStayAwakeNotifying:NO];
            Pump(0.1);

            // Simulate the shared CLI PID file changing while old metadata remains.
            NSTask *external = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/caffeinate" arguments:@[@"-i", @"-t", @"3"]];
            [@{ @"pid": @1, @"deadline": [NSDate dateWithTimeIntervalSinceNow:600] } writeToURL:[app sessionFile] atomically:YES];
            [[NSString stringWithFormat:@"%d", external.processIdentifier] writeToURL:[app pidFile] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            Pump(0.1);
            Check([app runningPid] == external.processIdentifier && ![app activeDeadline], @"CLI session ignores another PID's deadline");
            [app stopStayAwakeNotifying:NO];
            Pump(0.1);
            Check(!external.running, @"menu can stop CLI process");
            Check(app.notificationCount == 0 && app.alertCount == 1, @"only expected error and no expiry notifications");
            puts("ok - localized menu, timed session, extension, stop, expiry, wake, CLI state and write-failure tests");
        } @finally {
            [app stopStayAwakeNotifying:NO];
            [NSFileManager.defaultManager removeItemAtURL:app.testRoot error:nil];
        }
    }
    return 0;
}
