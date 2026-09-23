#import "LSIdentityTransferBundle.h"
#import <UIKit/UIKit.h>

static NSString *const kLSBundlePrefix = @"XSGPS1:";
static NSString *const kLSKnownHostUUIDKey = @"fc_uuidForDevice";

static BOOL LSIsSupportedHostUUID(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length < 16 || value.length > 128) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF-"];
    return [value rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}


@implementation LSIdentityTransferBundle

+ (nullable NSString *)supportedHostLocalIdentifier {
    NSString *identifier = [[NSUserDefaults standardUserDefaults] stringForKey:kLSKnownHostUUIDKey];
    return LSIsSupportedHostUUID(identifier) ? identifier : nil;
}

+ (NSString *)exportTextWithUUID:(NSString *)uuid transferCode:(NSString *)transferCode {
    NSString *sourceIDFV = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"غير متاح";
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"غير متاح";
    NSMutableDictionary *snapshot = [@{
        @"version": @1,
        @"xsgps_uuid": uuid ?: @"",
        @"transfer_code": transferCode ?: @"",
        @"source_idfv_read_only": sourceIDFV,
        @"source_app_bundle_read_only": bundleID
    } mutableCopy];
    // The attached Jodeluuid.dylib reads exactly this key from standardUserDefaults.
    // No bulk preferences or Keychain contents are exported.
    NSString *hostUUID = [self supportedHostLocalIdentifier];
    if (hostUUID && ![bundleID isEqualToString:@"غير متاح"]) {
        snapshot[@"host_local_uuid"] = hostUUID;
        snapshot[@"host_local_key"] = kLSKnownHostUUIDKey;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
    if (!json) return @"";
    return [kLSBundlePrefix stringByAppendingString:[json base64EncodedStringWithOptions:0]];
}

+ (nullable NSDictionary<NSString *, NSString *> *)parseText:(NSString *)text
                                           separateTransferCode:(nullable NSString *)code {
    NSString *input = [text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *uuid = input;
    NSString *token = [code ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *hostLocalUUID = nil;
    NSString *hostBundle = nil;
    if ([input hasPrefix:kLSBundlePrefix] || [input hasPrefix:@"{"]) {
        NSData *jsonData = nil;
        if ([input hasPrefix:kLSBundlePrefix]) {
            NSString *base64 = [input substringFromIndex:kLSBundlePrefix.length];
            jsonData = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
        } else {
            jsonData = [input dataUsingEncoding:NSUTF8StringEncoding];
        }
        if (!jsonData) return nil;
        id decoded = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (![decoded isKindOfClass:NSDictionary.class]) return nil;
        NSDictionary *record = (NSDictionary *)decoded;
        if (![record[@"version"] respondsToSelector:@selector(integerValue)] || [record[@"version"] integerValue] != 1) return nil;
        if (![record[@"xsgps_uuid"] isKindOfClass:NSString.class] ||
            ![record[@"transfer_code"] isKindOfClass:NSString.class]) return nil;
        uuid = record[@"xsgps_uuid"];
        token = record[@"transfer_code"];
        if (record[@"host_local_uuid"]) {
            if (![record[@"host_local_uuid"] isKindOfClass:NSString.class] ||
                ![record[@"host_local_key"] isEqual:kLSKnownHostUUIDKey] ||
                ![record[@"source_app_bundle_read_only"] isKindOfClass:NSString.class]) return nil;
            hostLocalUUID = record[@"host_local_uuid"];
            hostBundle = record[@"source_app_bundle_read_only"];
            if (!LSIsSupportedHostUUID(hostLocalUUID) ||
                hostBundle.length == 0 || hostBundle.length > 256) return nil;
        }
    } else if ([input containsString:@"|"] && token.length == 0) {
        NSArray<NSString *> *parts = [input componentsSeparatedByString:@"|"];
        if (parts.count != 2) return nil;
        uuid = parts[0];
        token = parts[1];
    }
    uuid = [[uuid stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    token = [[token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    NSUUID *validUUID = [[NSUUID alloc] initWithUUIDString:uuid];
    if (!validUUID || token.length < 16 || token.length > 256) return nil;
    NSMutableDictionary<NSString *, NSString *> *parsed = [@{
        @"uuid":validUUID.UUIDString, @"token":token
    } mutableCopy];
    if (hostLocalUUID) {
        parsed[@"host_local_uuid"] = hostLocalUUID;
        parsed[@"host_bundle"] = hostBundle;
    }
    return parsed;
}

+ (nullable NSString *)hostIdentityImportErrorForRecord:(NSDictionary<NSString *, NSString *> *)record {
    NSString *hostUUID = record[@"host_local_uuid"];
    if (!hostUUID.length) return nil; // Legacy bundle: XsGpS-only transfer remains supported.
    NSString *hostBundle = record[@"host_bundle"];
    NSString *currentBundle = NSBundle.mainBundle.bundleIdentifier;
    if (!LSIsSupportedHostUUID(hostUUID) || !hostBundle.length) {
        return @"المعرّف المحلي داخل الحزمة غير صالح.";
    }
    if (!currentBundle.length || ![currentBundle isEqualToString:hostBundle]) {
        return @"هوية التطبيق المحلي مرتبطة بتطبيق مختلف. استخدم نفس التطبيق على الجهاز الجديد.";
    }
    return nil;
}

+ (BOOL)restoreVerifiedHostLocalIdentifierFromRecord:(NSDictionary<NSString *, NSString *> *)record {
    NSString *hostUUID = record[@"host_local_uuid"];
    if (!hostUUID.length) return YES;
    if ([self hostIdentityImportErrorForRecord:record]) return NO;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:hostUUID forKey:kLSKnownHostUUIDKey];
    [defaults synchronize];
    // Some host apps cache this preference and must be restarted to read it again.
    return [[defaults stringForKey:kLSKnownHostUUIDKey] isEqualToString:hostUUID];
}

+ (NSString *)identitySummaryWithUUID:(NSString *)uuid {
    NSString *idfv = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"غير متاح";
    NSString *hostBundle = NSBundle.mainBundle.bundleIdentifier ?: @"غير متاح";
    NSString *hostUUID = [self supportedHostLocalIdentifier];
    NSString *hostLine = hostUUID.length ? [NSString stringWithFormat:@"UUID المحلي للتطبيق (fc_uuidForDevice):\n%@\n\n", hostUUID]
                                          : @"لم يُعثر على UUID محلي مدعوم في هذا التطبيق.\n\n";
    return [NSString stringWithFormat:@"هوية XsGpS:\n%@\n\n%@IDFV الحالي (مرجع فقط):\n%@\n\nالتطبيق المستضيف:\n%@\n\nلا يتم استنساخ IDFV أو هوية الآيفون الفعلية.", uuid ?: @"", hostLine, idfv, hostBundle];
}

@end
