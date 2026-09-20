#import "LSActivationManager.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

static NSString * const kLSActivationBaseURL = @"https://location-spoofer-api.hso0ooni14.workers.dev";
static NSString * const kLSActivationSuite = @"com.xsgps.activation";
static NSString * const kLSCodeKey = @"activation_code";
static NSString * const kLSDeviceIDKey = @"device_id";
static NSString * const kLSExpiresKey = @"expires_at";
static NSString * const kLSActiveKey = @"locally_active";
static NSString * const kLSLastVerifyKey = @"last_verify";
static NSTimeInterval const kLSVerifyInterval = 300.0;

@interface LSActivationManager ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, copy, readwrite) NSString *deviceID;
@property (nonatomic, copy, readwrite, nullable) NSString *activationCode;
@property (nonatomic, strong, readwrite, nullable) NSDate *expiresAt;
@property (nonatomic, assign) BOOL locallyActive;
@property (nonatomic, assign) BOOL verificationInFlight;
@end

@implementation LSActivationManager

+ (instancetype)shared {
    static LSActivationManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[LSActivationManager alloc] initPrivate];
    });
    return manager;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kLSActivationSuite];
        _activationCode = [_defaults stringForKey:kLSCodeKey];
        _expiresAt = [_defaults objectForKey:kLSExpiresKey];
        _locallyActive = [_defaults boolForKey:kLSActiveKey];
        _deviceID = [_defaults stringForKey:kLSDeviceIDKey];
        if (_deviceID.length == 0) {
            _deviceID = UIDevice.currentDevice.identifierForVendor.UUIDString ?: NSUUID.UUID.UUIDString;
            [_defaults setObject:_deviceID forKey:kLSDeviceIDKey];
        }
    }
    return self;
}

- (void)warmUp {
    (void)self.isActivated;
}

- (BOOL)isActivated {
    BOOL active = NO;
    BOOL shouldVerify = NO;
    @synchronized (self) {
        active = self.locallyActive && self.activationCode.length > 0;
        if (active && self.expiresAt && [self.expiresAt timeIntervalSinceNow] <= 0.0) {
            self.locallyActive = NO;
            [self.defaults setBool:NO forKey:kLSActiveKey];
            active = NO;
        }

        if (active && !self.verificationInFlight) {
            NSDate *last = [self.defaults objectForKey:kLSLastVerifyKey];
            if (!last || [[NSDate date] timeIntervalSinceDate:last] >= kLSVerifyInterval) {
                self.verificationInFlight = YES;
                shouldVerify = YES;
            }
        }
    }

    if (shouldVerify) {
        [self verifyWithAlreadyMarkedInFlight:YES completion:nil];
    }
    return active;
}

- (NSString *)deviceModelIdentifier {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *identifier = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    return identifier.length ? identifier : UIDevice.currentDevice.model;
}

- (NSDictionary *)devicePayloadWithCode:(NSString *)code {
    UIDevice *device = UIDevice.currentDevice;
    NSString *appVersion = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"1.0";
    return @{
        @"code": code ?: @"",
        @"device_id": self.deviceID ?: @"",
        @"device_name": device.name ?: @"iPhone",
        @"device_udid": self.deviceID ?: @"",
        @"ios_version": device.systemVersion ?: @"",
        @"system_name": device.systemName ?: @"iOS",
        @"device_model": [self deviceModelIdentifier] ?: @"iPhone",
        @"app_version": appVersion
    };
}

- (NSDate *)dateFromServerString:(id)value {
    if (![value isKindOfClass:NSString.class] || [(NSString *)value length] == 0) {
        return nil;
    }
    NSString *string = (NSString *)value;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDate *date = [formatter dateFromString:string];
    if (date) return date;

    if (@available(iOS 10.0, *)) {
        NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
        return [iso dateFromString:string];
    }
    return nil;
}

- (void)saveSuccessfulCode:(NSString *)code response:(NSDictionary *)response {
    NSDate *expires = [self dateFromServerString:response[@"expires_at"]];
    @synchronized (self) {
        self.activationCode = code;
        self.expiresAt = expires;
        self.locallyActive = YES;
        [self.defaults setObject:code forKey:kLSCodeKey];
        [self.defaults setBool:YES forKey:kLSActiveKey];
        if (expires) {
            [self.defaults setObject:expires forKey:kLSExpiresKey];
        } else {
            [self.defaults removeObjectForKey:kLSExpiresKey];
        }
        [self.defaults setObject:[NSDate date] forKey:kLSLastVerifyKey];
    }
}

- (void)markInvalid {
    @synchronized (self) {
        self.locallyActive = NO;
        [self.defaults setBool:NO forKey:kLSActiveKey];
    }
}

- (void)postPath:(NSString *)path
            code:(NSString *)code
      completion:(void (^)(NSInteger statusCode, NSDictionary * _Nullable json, NSError * _Nullable error))completion {
    NSURL *url = [NSURL URLWithString:[kLSActivationBaseURL stringByAppendingString:path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSError *serializationError = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:[self devicePayloadWithCode:code]
                                                       options:0
                                                         error:&serializationError];
    if (serializationError) {
        if (completion) completion(0, nil, serializationError);
        return;
    }

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        NSDictionary *json = nil;
        if (data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:NSDictionary.class]) json = object;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(http.statusCode, json, error);
        });
    }];
    [task resume];
}

- (void)activateCode:(NSString *)code completion:(LSActivationCompletion)completion {
    NSString *normalized = [[[code ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                             uppercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (normalized.length == 0) {
        if (completion) completion(NO, @"أدخل كود التفعيل");
        return;
    }

    [self postPath:@"/activate" code:normalized completion:^(NSInteger statusCode, NSDictionary *json, NSError *error) {
        if (error || !json) {
            if (completion) completion(NO, @"تعذر الاتصال بسيرفر التفعيل");
            return;
        }
        BOOL ok = [json[@"ok"] boolValue];
        NSString *message = [json[@"message"] isKindOfClass:NSString.class] ? json[@"message"] : (ok ? @"تم التفعيل" : @"تعذر التفعيل");
        if (ok) {
            [self saveSuccessfulCode:normalized response:json];
        } else if (statusCode >= 400 && statusCode < 500) {
            [self markInvalid];
        }
        if (completion) completion(ok, message);
    }];
}

- (void)verifyNowWithCompletion:(LSActivationCompletion)completion {
    BOOL begin = NO;
    @synchronized (self) {
        if (!self.verificationInFlight) {
            self.verificationInFlight = YES;
            begin = YES;
        }
    }
    if (!begin) {
        if (completion) completion(self.isActivated, self.isActivated ? @"التفعيل صالح" : @"التفعيل غير صالح");
        return;
    }
    [self verifyWithAlreadyMarkedInFlight:YES completion:completion];
}

- (void)verifyWithAlreadyMarkedInFlight:(BOOL)marked completion:(LSActivationCompletion)completion {
    (void)marked;
    NSString *code = self.activationCode;
    if (code.length == 0) {
        @synchronized (self) { self.verificationInFlight = NO; }
        if (completion) completion(NO, @"لا يوجد كود مفعّل");
        return;
    }

    [self postPath:@"/verify" code:code completion:^(NSInteger statusCode, NSDictionary *json, NSError *error) {
        @synchronized (self) { self.verificationInFlight = NO; }
        if (error || !json) {
            // Network/5xx failures do not revoke a locally valid activation.
            if (completion) completion(self.locallyActive, @"تعذر التحقق من السيرفر حالياً");
            return;
        }

        BOOL ok = [json[@"ok"] boolValue];
        NSString *message = [json[@"message"] isKindOfClass:NSString.class] ? json[@"message"] : (ok ? @"التفعيل صالح" : @"التفعيل غير صالح");
        if (ok) {
            [self saveSuccessfulCode:code response:json];
        } else if (statusCode >= 400 && statusCode < 500) {
            [self markInvalid];
        }
        if (completion) completion(ok, message);
    }];
}

@end
