// Exercise the production session lifecycle with real, short-lived caffeinate tasks.
#define main StayAwakeApplicationMain
#import "../StayAwakeMenu/main.m"
#undef main

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
            [app configureStatusItem];
            Check(app.durationMenuItem.submenu.numberOfItems == 7, @"preset and custom actions present");
            Check(!app.extendMenuItem.enabled && app.statusItem.button.title.length == 0, @"off state has no countdown or extension");
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
            Check(app.statusItem.button.title.length == 0 && !app.extendMenuItem.enabled, @"expiration removes countdown and disables extension");
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
            Check(![app activeDeadline] && app.statusItem.button.title.length == 0 && !app.extendMenuItem.enabled, @"indefinite has no countdown or extension");
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
