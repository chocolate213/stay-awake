#import <Foundation/Foundation.h>

// Stable numeric versions only. Invalid versions must never be reported as up to date.
FOUNDATION_EXPORT BOOL CompareUpdateVersions(NSString *latest, NSString *current, NSComparisonResult *result);

@interface UpdateRelease : NSObject
@property(nonatomic, readonly, copy) NSString *version;
@property(nonatomic, readonly, copy) NSString *notes;
@property(nonatomic, readonly, strong) NSURL *pageURL;
+ (instancetype)releaseFromData:(NSData *)data response:(NSURLResponse *)response
                  networkError:(NSError *)error failureKey:(NSString **)failureKey;
@end
