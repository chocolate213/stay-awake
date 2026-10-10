#import "../StayAwakeMenu/UpdateRelease.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSHTTPURLResponse *Response(NSInteger status) {
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://api.github.com/"]
        statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil];
}
static NSData *Data(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingFragmentsAllowed error:NULL];
}
int main(void) {
    @autoreleasepool {
        NSComparisonResult result;
        Check(CompareUpdateVersions(@"1.10.0", @"1.9.9", &result) && result == NSOrderedDescending, @"numeric minor versions");
        Check(CompareUpdateVersions(@"2.0", @"1.99.99", &result) && result == NSOrderedDescending, @"major update");
        Check(CompareUpdateVersions(@"1.1", @"1.1.0", &result) && result == NSOrderedSame, @"missing zero components");
        Check(CompareUpdateVersions(@"1.1.1", @"1.2.0", &result) && result == NSOrderedAscending, @"local build newer than latest must not downgrade");
        for (id version in @[@"", @"v1.1.1", @"1.2.0-beta", @"1..2", @"1.2\n", @"-1", NSNull.null]) {
            Check(!CompareUpdateVersions(version, @"1.1.1", &result), @"invalid latest version rejected");
            Check(!CompareUpdateVersions(@"1.2.0", version, &result), @"invalid installed version rejected");
        }
        NSMutableDictionary *json = [@{@"tag_name": @"v1.2.0", @"body": @"  Release notes\n", @"draft": @NO,
            @"prerelease": @NO, @"html_url": @"https://untrusted.example/"} mutableCopy];
        NSString *failure = nil;
        UpdateRelease *release = [UpdateRelease releaseFromData:Data(json) response:Response(200) networkError:nil failureKey:&failure];
        Check(release && !failure && [release.version isEqualToString:@"1.2.0"], @"stable release parsed");
        Check([release.notes isEqualToString:@"Release notes"], @"notes trimmed");
        Check([release.pageURL.absoluteString isEqualToString:@"https://github.com/chocolate213/stay-awake/releases/tag/v1.2.0"], @"download destination remains in project");
        for (NSString *flag in @[@"draft", @"prerelease"]) {
            json[flag] = @YES;
            Check(![UpdateRelease releaseFromData:Data(json) response:Response(200) networkError:nil failureKey:&failure], @"draft and prerelease rejected");
            json[flag] = @NO;
        }
        for (id tag in @[NSNull.null, @123, @"../other", @"v1.2.0-beta"]) {
            json[@"tag_name"] = tag;
            Check(![UpdateRelease releaseFromData:Data(json) response:Response(200) networkError:nil failureKey:&failure], @"malformed tag rejected");
        }
        json[@"tag_name"] = @"v1.2.0";
        json[@"body"] = NSNull.null;
        release = [UpdateRelease releaseFromData:Data(json) response:Response(200) networkError:nil failureKey:&failure];
        Check(release && release.notes.length == 0 && !failure, @"missing notes supported and stale error cleared");
        json[@"body"] = [@"x" stringByPaddingToLength:9000 withString:@"x" startingAtIndex:0];
        release = [UpdateRelease releaseFromData:Data(json) response:Response(200) networkError:nil failureKey:&failure];
        Check(release.notes.length == 8001, @"long release notes bounded");
        for (NSNumber *status in @[@403, @429, @404, @500]) {
            Check(![UpdateRelease releaseFromData:Data(json) response:Response(status.integerValue) networkError:nil failureKey:&failure], @"HTTP failures are not up to date");
            Check([failure isEqualToString:(status.integerValue == 403 || status.integerValue == 429 ? @"updates.error.rateLimit" : @"updates.error.server")], @"use actionable HTTP failure reason");
        }
        for (NSData *invalid in @[Data(@[]), Data(@{@"tag_name": @"v1.2.0"}), [@"not json" dataUsingEncoding:NSUTF8StringEncoding], [NSMutableData dataWithLength:1024 * 1024 + 1]]) {
            Check(![UpdateRelease releaseFromData:invalid response:Response(200) networkError:nil failureKey:&failure] && [failure isEqualToString:@"updates.error.invalid"], @"invalid and oversized responses rejected");
        }
        for (NSNumber *code in @[@(NSURLErrorNotConnectedToInternet), @(NSURLErrorTimedOut), @(NSURLErrorCancelled)]) {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:code.integerValue userInfo:nil];
            Check(![UpdateRelease releaseFromData:nil response:nil networkError:error failureKey:&failure] && [failure isEqualToString:@"updates.error.network"], @"network failures do not report up to date");
        }
        puts("ok - update version, release validation, and failure tests");
    }
    return 0;
}
