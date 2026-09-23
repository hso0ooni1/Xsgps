#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One transferable XsGpS identity record. Source IDFV is reference-only:
/// iOS does not allow importing another phone's genuine system identity.
@interface LSIdentityTransferBundle : NSObject
+ (NSString *)exportTextWithUUID:(NSString *)uuid transferCode:(NSString *)transferCode;
+ (nullable NSDictionary<NSString *, NSString *> *)parseText:(NSString *)text
                                           separateTransferCode:(nullable NSString *)code;
+ (NSString *)identitySummaryWithUUID:(NSString *)uuid;
@end

NS_ASSUME_NONNULL_END
