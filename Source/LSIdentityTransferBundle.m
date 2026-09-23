#import "LSIdentityTransferBundle.h"
#import <UIKit/UIKit.h>

static NSString *const kLSBundlePrefix = @"XSGPS1:";

@implementation LSIdentityTransferBundle

+ (NSString *)exportTextWithUUID:(NSString *)uuid transferCode:(NSString *)transferCode {
    NSString *sourceIDFV = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"غير متاح";
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"غير متاح";
    NSDictionary *snapshot = @{
        @"version": @1,
        @"xsgps_uuid": uuid ?: @"",
        @"transfer_code": transferCode ?: @"",
        @"source_idfv_read_only": sourceIDFV,
        @"source_app_bundle_read_only": bundleID
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
    if (!json) return @"";
    return [kLSBundlePrefix stringByAppendingString:[json base64EncodedStringWithOptions:0]];
}

+ (nullable NSDictionary<NSString *, NSString *> *)parseText:(NSString *)text
                                           separateTransferCode:(nullable NSString *)code {
    NSString *input = [text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *uuid = input;
    NSString *token = [code ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
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
    return @{@"uuid":validUUID.UUIDString, @"token":token};
}

+ (NSString *)identitySummaryWithUUID:(NSString *)uuid {
    NSString *idfv = UIDevice.currentDevice.identifierForVendor.UUIDString ?: @"غير متاح";
    NSString *hostBundle = NSBundle.mainBundle.bundleIdentifier ?: @"غير متاح";
    return [NSString stringWithFormat:@"هوية XsGpS:\n%@\n\nIDFV الحالي (للعرض فقط):\n%@\n\nمعرف التطبيق المستضيف:\n%@\n\nIDFV وهوية الآيفون الفعلية لا يمكن استعادتهما على جهاز مختلف.", uuid ?: @"", idfv, hostBundle];
}

@end
