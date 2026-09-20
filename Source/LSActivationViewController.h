#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSActivationViewController : UIViewController
@property (nonatomic, copy, nullable) void (^activationSucceeded)(void);
@end

NS_ASSUME_NONNULL_END
