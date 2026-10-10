#import "UpdateRelease.h"

static BOOL IsUpdateVersion(NSString *version) {
    if (![version isKindOfClass:NSString.class] || version.length == 0 || version.length > 64) return NO;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]+(\\.[0-9]+){0,3}$" options:0 error:NULL];
    return [pattern numberOfMatchesInString:version options:0 range:NSMakeRange(0, version.length)] == 1 &&
        [version rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789."].invertedSet].location == NSNotFound;
}

BOOL CompareUpdateVersions(NSString *latest, NSString *current, NSComparisonResult *result) {
    if (!IsUpdateVersion(latest) || !IsUpdateVersion(current)) return NO;
    NSArray<NSString *> *left = [latest componentsSeparatedByString:@"."];
    NSArray<NSString *> *right = [current componentsSeparatedByString:@"."];
    NSComparisonResult comparison = NSOrderedSame;
    for (NSUInteger index = 0; index < MAX(left.count, right.count); index++) {
        NSString *a = index < left.count ? left[index] : @"0";
        NSString *b = index < right.count ? right[index] : @"0";
        comparison = [a compare:b options:NSNumericSearch];
        if (comparison != NSOrderedSame) break;
    }
    if (result) *result = comparison;
    return YES;
}

@interface UpdateRelease ()
@property(nonatomic, readwrite, copy) NSString *version;
@property(nonatomic, readwrite, copy) NSString *notes;
@property(nonatomic, readwrite, strong) NSURL *pageURL;
@end

@implementation UpdateRelease
+ (instancetype)releaseFromData:(NSData *)data response:(NSURLResponse *)response
                  networkError:(NSError *)error failureKey:(NSString **)failureKey {
    NSString *failure = nil;
    if (error) failure = @"updates.error.network";
    else if (![response isKindOfClass:NSHTTPURLResponse.class]) failure = @"updates.error.invalid";
    else {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (status == 403 || status == 429) failure = @"updates.error.rateLimit";
        else if (status != 200) failure = @"updates.error.server";
    }
    if (!failure && (!data || data.length > 1024 * 1024)) failure = @"updates.error.invalid";
    NSDictionary *json = failure ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (!failure && ![json isKindOfClass:NSDictionary.class]) failure = @"updates.error.invalid";
    NSString *tag = failure ? nil : json[@"tag_name"];
    NSString *version = [tag isKindOfClass:NSString.class] && [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
    if (!failure && (!IsUpdateVersion(version) ||
        ![json[@"draft"] isKindOfClass:NSNumber.class] || [json[@"draft"] boolValue] ||
        ![json[@"prerelease"] isKindOfClass:NSNumber.class] || [json[@"prerelease"] boolValue])) {
        failure = @"updates.error.invalid";
    }
    if (failure) {
        if (failureKey) *failureKey = failure;
        return nil;
    }
    UpdateRelease *release = [UpdateRelease new];
    release.version = version;
    NSString *notes = [json[@"body"] isKindOfClass:NSString.class] ? json[@"body"] : @"";
    notes = [notes stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    release.notes = notes.length > 8000 ? [[notes substringToIndex:8000] stringByAppendingString:@"…"] : notes;
    // Construct the destination from the validated tag, never from an arbitrary response URL.
    release.pageURL = [NSURL URLWithString:[@"https://github.com/chocolate213/stay-awake/releases/tag/" stringByAppendingString:tag]];
    if (failureKey) *failureKey = nil;
    return release;
}
@end
