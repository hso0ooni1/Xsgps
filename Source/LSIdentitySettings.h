#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A small, allowlisted backup of XsGpS preferences and bookmarks.
@interface LSIdentitySettings : NSObject
+ (NSDictionary<NSString *, id> *)exportSettings;
+ (void)importSettings:(NSDictionary<NSString *, id> *)settings;
@end

NS_ASSUME_NONNULL_END
