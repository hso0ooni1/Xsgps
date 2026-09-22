#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LSActivationCompletion)(BOOL success, NSString *message);
typedef void (^LSIdentityTransferCompletion)(BOOL success, NSString *message, NSString * _Nullable transferCode);

@interface LSActivationManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isActivated) BOOL activated;
@property (nonatomic, copy, readonly) NSString *deviceID;
@property (nonatomic, copy, readonly) NSString *installationUUID;
@property (nonatomic, copy, readonly, nullable) NSString *activationCode;
@property (nonatomic, strong, readonly, nullable) NSDate *expiresAt;

- (void)warmUp;
/// The current activated device generates a one-time ten-minute transfer code.
- (void)prepareIdentityTransferWithCompletion:(LSIdentityTransferCompletion)completion;
/// The new installation imports its previous XsGpS identity after one-time verification.
- (void)completeIdentityTransferFromUUID:(NSString *)oldUUID transferCode:(NSString *)transferCode completion:(LSActivationCompletion)completion;
- (void)activateCode:(NSString *)code completion:(LSActivationCompletion)completion;
- (void)verifyNowWithCompletion:(nullable LSActivationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
