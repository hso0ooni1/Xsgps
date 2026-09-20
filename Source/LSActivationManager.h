#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LSActivationCompletion)(BOOL success, NSString *message);

@interface LSActivationManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isActivated) BOOL activated;
@property (nonatomic, copy, readonly) NSString *deviceID;
@property (nonatomic, copy, readonly, nullable) NSString *activationCode;
@property (nonatomic, strong, readonly, nullable) NSDate *expiresAt;

- (void)warmUp;
- (void)activateCode:(NSString *)code completion:(LSActivationCompletion)completion;
- (void)verifyNowWithCompletion:(nullable LSActivationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
