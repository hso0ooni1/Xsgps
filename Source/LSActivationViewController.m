#import "LSActivationViewController.h"
#import "LSActivationManager.h"
#import "LSIdentityTransferBundle.h"

@interface LSActivationViewController ()
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UIButton *activateButton;
@property (nonatomic, strong) UIButton *restoreButton;
@property (nonatomic, strong) UILabel *messageLabel;
@end

@implementation LSActivationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithRed:0.055 green:0.063 blue:0.082 alpha:0.98];
    card.layer.cornerRadius = 26.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.36;
    card.layer.shadowRadius = 22.0;
    card.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    card.layer.masksToBounds = NO;
    [self.view addSubview:card];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"location.north.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor colorWithRed:1.0 green:0.20 blue:0.24 alpha:1.0];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"XsGpS";
    title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBlack];
    title.textColor = UIColor.whiteColor;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"تفعيل أداة تغيير الموقع";
    subtitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    subtitle.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    subtitle.textAlignment = NSTextAlignmentCenter;
    [card addSubview:subtitle];

    self.codeField = [[UITextField alloc] init];
    self.codeField.translatesAutoresizingMaskIntoConstraints = NO;
    self.codeField.placeholder = @"أدخل كود التفعيل";
    self.codeField.textAlignment = NSTextAlignmentCenter;
    self.codeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.codeField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.codeField.textContentType = UITextContentTypeOneTimeCode;
    self.codeField.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightSemibold];
    self.codeField.textColor = UIColor.whiteColor;
    self.codeField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    self.codeField.layer.cornerRadius = 14.0;
    self.codeField.layer.cornerCurve = kCACornerCurveContinuous;
    self.codeField.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.codeField.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    [card addSubview:self.codeField];

    self.activateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.activateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activateButton setTitle:@"تفعيل" forState:UIControlStateNormal];
    [self.activateButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.activateButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.activateButton.backgroundColor = [UIColor colorWithRed:0.92 green:0.10 blue:0.16 alpha:1.0];
    self.activateButton.layer.cornerRadius = 14.0;
    self.activateButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.activateButton addTarget:self action:@selector(activateTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.activateButton];

    self.restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.restoreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.restoreButton setTitle:@"استعادة هوية التطبيق" forState:UIControlStateNormal];
    [self.restoreButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.restoreButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.restoreButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    self.restoreButton.layer.cornerRadius = 12.0;
    [self.restoreButton addTarget:self action:@selector(restoreIdentityTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.restoreButton];

    self.messageLabel = [[UILabel alloc] init];
    self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.messageLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.messageLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.numberOfLines = 0;
    [card addSubview:self.messageLabel];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = [UIColor colorWithWhite:0.68 alpha:1.0];
    close.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    close.layer.cornerRadius = 18.0;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:close];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:22.0],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-22.0],
        [card.widthAnchor constraintLessThanOrEqualToConstant:430.0],
        [card.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.86],

        [close.topAnchor constraintEqualToAnchor:card.topAnchor constant:13.0],
        [close.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-13.0],
        [close.widthAnchor constraintEqualToConstant:36.0],
        [close.heightAnchor constraintEqualToConstant:36.0],

        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:22.0],
        [icon.centerXAnchor constraintEqualToAnchor:card.centerXAnchor constant:-58.0],
        [icon.widthAnchor constraintEqualToConstant:34.0],
        [icon.heightAnchor constraintEqualToConstant:34.0],

        [title.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10.0],

        [subtitle.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:14.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [subtitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],

        [self.codeField.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:17.0],
        [self.codeField.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [self.codeField.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],
        [self.codeField.heightAnchor constraintEqualToConstant:48.0],

        [self.activateButton.topAnchor constraintEqualToAnchor:self.codeField.bottomAnchor constant:14.0],
        [self.activateButton.leadingAnchor constraintEqualToAnchor:self.codeField.leadingAnchor],
        [self.activateButton.trailingAnchor constraintEqualToAnchor:self.codeField.trailingAnchor],
        [self.activateButton.heightAnchor constraintEqualToConstant:46.0],

        [self.restoreButton.topAnchor constraintEqualToAnchor:self.activateButton.bottomAnchor constant:9.0],
        [self.restoreButton.leadingAnchor constraintEqualToAnchor:self.codeField.leadingAnchor],
        [self.restoreButton.trailingAnchor constraintEqualToAnchor:self.codeField.trailingAnchor],
        [self.restoreButton.heightAnchor constraintEqualToConstant:41.0],

        [self.messageLabel.topAnchor constraintEqualToAnchor:self.restoreButton.bottomAnchor constant:12.0],
        [self.messageLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [self.messageLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],
        [self.messageLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-19.0],
    ]];
}

- (void)restoreIdentityTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"استعادة هوية XsGpS"
                                                                 message:@"الصق حزمة نقل XsGpS من الجهاز القديم. تبقى هوية الآيفون الجديد الحقيقية كما هي."
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"حزمة النقل أو UUID القديم";
        field.textAlignment = NSTextAlignmentLeft;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"رمز النقل (إذا لم تلصقه أعلاه)";
        field.textAlignment = NSTextAlignmentLeft;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"استعادة" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSDictionary<NSString *, NSString *> *record =
            [LSIdentityTransferBundle parseText:alert.textFields.firstObject.text
                            separateTransferCode:alert.textFields.lastObject.text];
        if (!record) {
            self.messageLabel.text = @"حزمة النقل غير صحيحة أو ناقصة.";
            self.messageLabel.textColor = [UIColor colorWithRed:1 green:0.40 blue:0.40 alpha:1];
            return;
        }
        NSString *hostError = [LSIdentityTransferBundle hostIdentityImportErrorForRecord:record];
        if (hostError) {
            self.messageLabel.text = hostError;
            self.messageLabel.textColor = [UIColor colorWithRed:1 green:0.40 blue:0.40 alpha:1];
            return;
        }
        NSString *uuid = record[@"uuid"];
        NSString *token = record[@"token"];
        self.restoreButton.enabled = NO;
        self.messageLabel.text = @"جاري التحقق من ملكية الهوية...";
        self.messageLabel.textColor = UIColor.whiteColor;
        [[LSActivationManager shared] completeIdentityTransferFromUUID:uuid transferCode:token completion:^(BOOL success, NSString *message) {
            self.restoreButton.enabled = YES;
            NSString *result = message;
            if (success && record[@"host_local_uuid"]) {
                BOOL applied = [LSIdentityTransferBundle restoreVerifiedHostLocalIdentifierFromRecord:record];
                result = [message stringByAppendingString:applied
                    ? @" تم أيضًا استعادة UUID المحلي. قد تحتاج إلى إعادة فتح التطبيق."
                    : @" استعيدت هوية XsGpS فقط؛ تعذر كتابة UUID المحلي."];
            }
            self.messageLabel.text = result;
            self.messageLabel.textColor = success ? [UIColor colorWithRed:0.28 green:0.92 blue:0.50 alpha:1] : [UIColor colorWithRed:1 green:0.40 blue:0.40 alpha:1];
            if (success) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    void (^completion)(void) = self.activationSucceeded;
                    [self dismissViewControllerAnimated:YES completion:completion];
                });
            }
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)activateTapped {
    NSString *code = self.codeField.text ?: @"";
    self.activateButton.enabled = NO;
    [self.activateButton setTitle:@"جاري التفعيل..." forState:UIControlStateNormal];
    self.messageLabel.text = @"جاري الاتصال بسيرفر XsGpS";
    self.messageLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];

    __weak typeof(self) weakSelf = self;
    [[LSActivationManager shared] activateCode:code completion:^(BOOL success, NSString *message) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.activateButton.enabled = YES;
        [self.activateButton setTitle:@"تفعيل" forState:UIControlStateNormal];
        self.messageLabel.text = message;
        self.messageLabel.textColor = success ? [UIColor colorWithRed:0.20 green:0.90 blue:0.45 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.32 blue:0.36 alpha:1.0];
        if (success) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                void (^completion)(void) = self.activationSucceeded;
                [self dismissViewControllerAnimated:YES completion:completion];
            });
        }
    }];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
