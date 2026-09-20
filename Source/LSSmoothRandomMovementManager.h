#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSSmoothRandomMovementManager : NSObject
+ (instancetype)shared;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) double radius;
- (void)restoreIfNeeded;
- (void)setEnabled:(BOOL)enabled anchorCoordinate:(CLLocationCoordinate2D)coordinate;
- (void)resetAnchorToCoordinate:(CLLocationCoordinate2D)coordinate;
@end

NS_ASSUME_NONNULL_END
