#import "LSIdentitySettings.h"
#import "PersistenceManager.h"
#import "BookmarksManager.h"
#import "LSSmoothRandomMovementManager.h"

static NSString * const kPrefsSuite = @"com.xsgps.dylib";
static NSString * const kBookmarksSuite = @"com.locationspoofer.dylib";

@implementation LSIdentitySettings

+ (NSArray<NSString *> *)numericPreferenceKeys {
    return @[@"spoof_latitude", @"spoof_longitude", @"LSAltitude",
             @"LSHeading", @"LSFluctuationRadius", @"LSSmoothRandomRadius",
             @"LSSmoothRandomAnchorLat", @"LSSmoothRandomAnchorLon"];
}

+ (NSDictionary<NSString *, id> *)exportSettings {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuite];
    NSUserDefaults *bookmarks = [[NSUserDefaults alloc] initWithSuiteName:kBookmarksSuite];
    NSMutableDictionary *numbers = [NSMutableDictionary dictionary];
    for (NSString *key in [self numericPreferenceKeys]) {
        id value = [prefs objectForKey:key];
        if ([value isKindOfClass:NSNumber.class]) numbers[key] = value;
    }
    NSArray *saved = [bookmarks arrayForKey:@"LSBookmarks"];
    NSMutableArray *safeBookmarks = [NSMutableArray array];
    for (id item in saved) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *name = [item[@"LSBMName"] isKindOfClass:NSString.class] ? item[@"LSBMName"] : @"موقع محفوظ";
        NSNumber *lat = item[@"LSBMLat"];
        NSNumber *lon = item[@"LSBMLon"];
        if (![lat isKindOfClass:NSNumber.class] || ![lon isKindOfClass:NSNumber.class]) continue;
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(lat.doubleValue, lon.doubleValue);
        if (!CLLocationCoordinate2DIsValid(coordinate)) continue;
        NSMutableDictionary *bookmark = [@{@"LSBMName": [name substringToIndex:MIN(name.length, 120)],
                                            @"LSBMLat": lat, @"LSBMLon": lon} mutableCopy];
        if ([item[@"LSBMDate"] isKindOfClass:NSString.class]) bookmark[@"LSBMDate"] = item[@"LSBMDate"];
        [safeBookmarks addObject:bookmark];
        if (safeBookmarks.count == 50) break;
    }
    return @{@"version": @1, @"preferences": numbers, @"bookmarks": safeBookmarks};
}

+ (void)importSettings:(NSDictionary<NSString *, id> *)settings {
    if (![settings isKindOfClass:NSDictionary.class]) return;
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:kPrefsSuite];
    NSDictionary *numbers = [settings[@"preferences"] isKindOfClass:NSDictionary.class] ? settings[@"preferences"] : @{};
    for (NSString *key in [self numericPreferenceKeys]) {
        id value = numbers[key];
        if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) continue;
        if ([key isEqualToString:@"spoof_latitude"] && fabs([value doubleValue]) > 90.0) continue;
        if ([key isEqualToString:@"spoof_longitude"] && fabs([value doubleValue]) > 180.0) continue;
        [prefs setObject:value forKey:key];
    }
    // Imported settings must never silently enable simulated location on a new installation.
    [prefs setBool:NO forKey:@"spoof_enabled"];
    [prefs setBool:NO forKey:@"LSSmoothRandomEnabled"];
    [prefs setBool:NO forKey:@"LSFluctuationEnabled"];
    NSArray *saved = [settings[@"bookmarks"] isKindOfClass:NSArray.class] ? settings[@"bookmarks"] : @[];
    NSMutableArray *clean = [NSMutableArray array];
    for (id item in saved) {
        LSBookmark *bookmark = [LSBookmark bookmarkFromDictionary:item];
        if (!bookmark || !CLLocationCoordinate2DIsValid(bookmark.coordinate)) continue;
        [clean addObject:[bookmark dictionaryRepresentation]];
        if (clean.count == 50) break;
    }
    NSUserDefaults *bookmarks = [[NSUserDefaults alloc] initWithSuiteName:kBookmarksSuite];
    [bookmarks setObject:clean forKey:@"LSBookmarks"];
    [[BookmarksManager shared] reloadAfterTransfer];
    [PersistenceManager loadEarly];
    NSNumber *radius = numbers[@"LSSmoothRandomRadius"];
    if ([radius isKindOfClass:NSNumber.class] && isfinite(radius.doubleValue)) {
        [LSSmoothRandomMovementManager shared].radius = radius.doubleValue;
    }
    if ([PersistenceManager shared].hasStoredCoordinate) {
        [[LSSmoothRandomMovementManager shared] resetAnchorToCoordinate:[PersistenceManager shared].spoofCoordinate];
    }
}

@end
