#import "LSSmoothRandomMovementManager.h"
#import "PersistenceManager.h"
#import <math.h>

static NSString * const kLSSmoothEnabledKey = @"LSSmoothRandomEnabled";
static NSString * const kLSSmoothRadiusKey = @"LSSmoothRandomRadius";
static NSString * const kLSSmoothAnchorLatKey = @"LSSmoothRandomAnchorLat";
static NSString * const kLSSmoothAnchorLonKey = @"LSSmoothRandomAnchorLon";
static NSString * const kLSSuiteName = @"com.xsgps.dylib";

@interface LSSmoothRandomMovementManager ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, assign) CLLocationCoordinate2D anchorCoordinate;
@property (nonatomic, assign) CLLocationCoordinate2D currentCoordinate;
@property (nonatomic, assign) CLLocationCoordinate2D targetCoordinate;
@property (nonatomic, assign) BOOL hasAnchor;
@property (nonatomic, assign) BOOL hasTarget;
@end

@implementation LSSmoothRandomMovementManager

+ (instancetype)shared {
    static LSSmoothRandomMovementManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LSSmoothRandomMovementManager alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kLSSuiteName];
        _enabled = [_defaults boolForKey:kLSSmoothEnabledKey];
        _radius = [_defaults doubleForKey:kLSSmoothRadiusKey];
        if (_radius <= 0.0) _radius = 50.0;
        if ([_defaults objectForKey:kLSSmoothAnchorLatKey] &&
            [_defaults objectForKey:kLSSmoothAnchorLonKey]) {
            CLLocationCoordinate2D anchor = CLLocationCoordinate2DMake(
                [_defaults doubleForKey:kLSSmoothAnchorLatKey],
                [_defaults doubleForKey:kLSSmoothAnchorLonKey]);
            if (CLLocationCoordinate2DIsValid(anchor)) {
                _anchorCoordinate = anchor;
                _currentCoordinate = anchor;
                _hasAnchor = YES;
            }
        }
    }
    return self;
}

- (void)restoreIfNeeded {
    [PersistenceManager shared].fluctuationEnabled = NO;
    if (!self.hasAnchor && [PersistenceManager shared].hasStoredCoordinate) {
        [self resetAnchorToCoordinate:[PersistenceManager shared].spoofCoordinate];
    }
    if (self.enabled && self.hasAnchor) [self startTimerIfNeeded];
}

- (void)setRadius:(double)radius {
    _radius = MAX(1.0, MIN(5000.0, radius));
    [self.defaults setDouble:_radius forKey:kLSSmoothRadiusKey];
    self.hasTarget = NO;
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == _enabled) return;
    _enabled = enabled;
    [self.defaults setBool:enabled forKey:kLSSmoothEnabledKey];
    [PersistenceManager shared].fluctuationEnabled = NO;
    if (enabled) {
        if (!self.hasAnchor && [PersistenceManager shared].hasStoredCoordinate) {
            [self resetAnchorToCoordinate:[PersistenceManager shared].spoofCoordinate];
        }
        [self startTimerIfNeeded];
    } else {
        [self stopTimer];
        if (self.hasAnchor) {
            BOOL spoofing = [PersistenceManager shared].isSpoofingEnabled;
            [[PersistenceManager shared] setSpoofCoordinate:self.anchorCoordinate enabled:spoofing];
            self.currentCoordinate = self.anchorCoordinate;
        }
        self.hasTarget = NO;
    }
}

- (void)setEnabled:(BOOL)enabled anchorCoordinate:(CLLocationCoordinate2D)coordinate {
    if (CLLocationCoordinate2DIsValid(coordinate)) [self resetAnchorToCoordinate:coordinate];
    self.enabled = enabled;
    if (enabled) [self startTimerIfNeeded];
}

- (void)resetAnchorToCoordinate:(CLLocationCoordinate2D)coordinate {
    if (!CLLocationCoordinate2DIsValid(coordinate)) return;
    self.anchorCoordinate = coordinate;
    self.currentCoordinate = coordinate;
    self.hasAnchor = YES;
    self.hasTarget = NO;
    [self.defaults setDouble:coordinate.latitude forKey:kLSSmoothAnchorLatKey];
    [self.defaults setDouble:coordinate.longitude forKey:kLSSmoothAnchorLonKey];
    BOOL spoofing = [PersistenceManager shared].isSpoofingEnabled;
    [[PersistenceManager shared] setSpoofCoordinate:coordinate enabled:spoofing];
}

- (void)startTimerIfNeeded {
    if (self.timer || !self.enabled || !self.hasAnchor) return;
    self.timer = [NSTimer timerWithTimeInterval:0.12 target:self selector:@selector(handleTick) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
}

- (double)distanceMetersFrom:(CLLocationCoordinate2D)a to:(CLLocationCoordinate2D)b {
    double meanLat = ((a.latitude + b.latitude) * 0.5) * M_PI / 180.0;
    double dy = (b.latitude - a.latitude) * 111320.0;
    double dx = (b.longitude - a.longitude) * 111320.0 * MAX(0.000001, cos(meanLat));
    return hypot(dx, dy);
}

- (CLLocationCoordinate2D)coordinateFrom:(CLLocationCoordinate2D)origin offsetEastMeters:(double)east offsetNorthMeters:(double)north {
    double lat = origin.latitude + north / 111320.0;
    double cosLat = MAX(0.000001, cos(origin.latitude * M_PI / 180.0));
    double lon = origin.longitude + east / (111320.0 * cosLat);
    return CLLocationCoordinate2DMake(lat, lon);
}

- (void)chooseNextTarget {
    double maxRadius = MAX(1.0, self.radius);
    double minDistance = MIN(maxRadius, MAX(2.0, maxRadius * 0.18));
    double unit = (double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX;
    double distance = minDistance + (maxRadius - minDistance) * sqrt(unit);
    double angle = ((double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX) * 2.0 * M_PI;
    self.targetCoordinate = [self coordinateFrom:self.anchorCoordinate
                                offsetEastMeters:sin(angle) * distance
                               offsetNorthMeters:cos(angle) * distance];
    self.hasTarget = YES;
}

- (void)handleTick {
    if (!self.enabled || !self.hasAnchor) return;
    if (!self.hasTarget) [self chooseNextTarget];
    double remaining = [self distanceMetersFrom:self.currentCoordinate to:self.targetCoordinate];
    if (remaining < 0.35) { self.hasTarget = NO; return; }
    const double stepMeters = 1.15 * 0.12;
    double fraction = MIN(1.0, stepMeters / MAX(remaining, 0.001));
    CLLocationDegrees lat = self.currentCoordinate.latitude + (self.targetCoordinate.latitude - self.currentCoordinate.latitude) * fraction;
    CLLocationDegrees lon = self.currentCoordinate.longitude + (self.targetCoordinate.longitude - self.currentCoordinate.longitude) * fraction;
    CLLocationCoordinate2D next = CLLocationCoordinate2DMake(lat, lon);
    if ([self distanceMetersFrom:self.anchorCoordinate to:next] > self.radius + 0.5) { self.hasTarget = NO; return; }
    self.currentCoordinate = next;
    BOOL spoofing = [PersistenceManager shared].isSpoofingEnabled;
    [[PersistenceManager shared] setTransientSpoofCoordinate:next enabled:spoofing];
}

@end
