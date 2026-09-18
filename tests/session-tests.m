// Exercise the production session lifecycle with real, short-lived caffeinate tasks.
#define main StayAwakeApplicationMain
#import "../StayAwakeMenu/main.m"
#undef main

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
@end
@implementation TestApp
- (NSURL *)applicationSupportDirectory { return self.testRoot; }
- (NSURL *)bundledHelperURL { return self.helperSource; }
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
