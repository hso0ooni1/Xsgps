#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One transferable XsGpS identity record. Source IDFV is reference-only:
/// iOS does not allow importing another phone's genuine system identity.
@interface LSIdentityTransferBundle : NSObject
+ (NSString *)exportTextWithUUID:(NSString *)uuid transferCode:(NSString *)transferCode;
+ (nullable NSDictionary<NSString *, NSString *> *)parseText:(NSString *)text
                                           separateTransferCode:(nullable NSString *)code;
/// Jodel-compatible apps may store a separate local identifier in this exact preference key.
+ (nullable NSString *)supportedHostLocalIdentifier;
/// Validates optional same-host identity fields before a one-time server token is consumed.
+ (nullable NSString *)hostIdentityImportErrorForRecord:(NSDictionary<NSString *, NSString *> *)record;
/// Only call after the server has successfully verified the owner's transfer token.
+ (BOOL)restoreVerifiedHostLocalIdentifierFromRecord:(NSDictionary<NSString *, NSString *> *)record;
+ (NSString *)identitySummaryWithUUID:(NSString *)uuid;
@end

NS_ASSUME_NONNULL_END
