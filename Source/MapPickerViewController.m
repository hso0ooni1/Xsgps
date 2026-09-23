#import "MapPickerViewController.h"
#import "PersistenceManager.h"
#import "BookmarksManager.h"
#import "LocationSpoofer.h"
#import "LSActivationManager.h"
#import "LSIdentityTransferBundle.h"
#import "OverlayWindow.h"
#import "LSSmoothRandomMovementManager.h"

#import <MapKit/MapKit.h>
#import <math.h>

static NSString *LSNormalizeCoordinateSearchText(NSString *input) {
    if (input.length == 0) return @"";

    NSMutableString *text = [input mutableCopy];
    NSArray<NSString *> *arabicDigits = @[@"٠", @"١", @"٢", @"٣", @"٤", @"٥", @"٦", @"٧", @"٨", @"٩"];
    NSArray<NSString *> *persianDigits = @[@"۰", @"۱", @"۲", @"۳", @"۴", @"۵", @"۶", @"۷", @"۸", @"۹"];
    for (NSUInteger i = 0; i < 10; i++) {
        NSString *ascii = [NSString stringWithFormat:@"%lu", (unsigned long)i];
        [text replaceOccurrencesOfString:arabicDigits[i] withString:ascii options:0 range:NSMakeRange(0, text.length)];
        [text replaceOccurrencesOfString:persianDigits[i] withString:ascii options:0 range:NSMakeRange(0, text.length)];
    }

    [text replaceOccurrencesOfString:@"٫" withString:@"." options:0 range:NSMakeRange(0, text.length)];
    [text replaceOccurrencesOfString:@"−" withString:@"-" options:0 range:NSMakeRange(0, text.length)];
    [text replaceOccurrencesOfString:@"–" withString:@"-" options:0 range:NSMakeRange(0, text.length)];
    [text replaceOccurrencesOfString:@"٬" withString:@"" options:0 range:NSMakeRange(0, text.length)];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *decoded = [trimmed stringByRemovingPercentEncoding];
    return decoded.length ? decoded : trimmed;
}

static BOOL LSCoordinateFromPair(double first, double second, CLLocationCoordinate2D *coordinate) {
    BOOL normal = first >= -90.0 && first <= 90.0 && second >= -180.0 && second <= 180.0;
    BOOL swapped = first >= -180.0 && first <= 180.0 && second >= -90.0 && second <= 90.0;

    CLLocationDegrees latitude = first;
    CLLocationDegrees longitude = second;

    // If the first value cannot be latitude but the second can, infer lon/lat automatically.
    if (!normal && swapped) {
        latitude = second;
        longitude = first;
        normal = YES;
    }

    if (!normal) return NO;
    CLLocationCoordinate2D value = CLLocationCoordinate2DMake(latitude, longitude);
    if (!CLLocationCoordinate2DIsValid(value)) return NO;
    if (coordinate) *coordinate = value;
    return YES;
}

static BOOL LSParseCoordinateSearchQuery(NSString *query, CLLocationCoordinate2D *coordinate) {
    NSString *normalized = LSNormalizeCoordinateSearchText(query);
    if (normalized.length == 0) return NO;

    // Google Maps place links often contain the precise pin as !3dLAT!4dLON.
    // Prefer that over the /@lat,lon viewport center when both are present.
    if ([normalized rangeOfString:@"google" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [normalized rangeOfString:@"maps" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        NSRegularExpression *pinPair = [NSRegularExpression regularExpressionWithPattern:@"!3d([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+))!4d([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+))"
                                                                                 options:NSRegularExpressionCaseInsensitive
                                                                                   error:nil];
        NSTextCheckingResult *pinMatch = [pinPair firstMatchInString:normalized options:0 range:NSMakeRange(0, normalized.length)];
        if (pinMatch.numberOfRanges == 3) {
            double lat = [[normalized substringWithRange:[pinMatch rangeAtIndex:1]] doubleValue];
            double lon = [[normalized substringWithRange:[pinMatch rangeAtIndex:2]] doubleValue];
            if (LSCoordinateFromPair(lat, lon, coordinate)) return YES;
        }

        // Full Google/Apple map URLs commonly contain /@lat,lon, ?q=lat,lon, ll=lat,lon, etc.
        NSRegularExpression *urlPair = [NSRegularExpression regularExpressionWithPattern:@"([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+))\\s*[,،]\\s*([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+))"
                                                                                 options:0
                                                                                   error:nil];
        NSTextCheckingResult *match = [urlPair firstMatchInString:normalized options:0 range:NSMakeRange(0, normalized.length)];
        if (match.numberOfRanges == 3) {
            double first = [[normalized substringWithRange:[match rangeAtIndex:1]] doubleValue];
            double second = [[normalized substringWithRange:[match rangeAtIndex:2]] doubleValue];
            if (LSCoordinateFromPair(first, second, coordinate)) return YES;
        }
    }

    NSMutableString *clean = [[normalized lowercaseString] mutableCopy];
    NSArray<NSString *> *labels = @[
        @"latitude", @"longitude", @"lat", @"lng", @"lon",
        @"خط العرض", @"خط الطول", @"العرض", @"الطول"
    ];
    for (NSString *label in labels) {
        [clean replaceOccurrencesOfString:label withString:@" " options:NSCaseInsensitiveSearch range:NSMakeRange(0, clean.length)];
    }

    NSArray<NSString *> *separators = @[
        @",", @"،", @";", @"؛", @"|", @"/",
        @"(", @")", @"[", @"]", @"{", @"}", @":", @"="
    ];
    for (NSString *separator in separators) {
        [clean replaceOccurrencesOfString:separator withString:@" " options:0 range:NSMakeRange(0, clean.length)];
    }

    NSArray<NSString *> *rawParts = [clean componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:2];
    for (NSString *part in rawParts) {
        if (part.length > 0) [parts addObject:part];
    }
    if (parts.count != 2) return NO;

    NSScanner *firstScanner = [NSScanner scannerWithString:parts[0]];
    NSScanner *secondScanner = [NSScanner scannerWithString:parts[1]];
    double first = 0.0;
    double second = 0.0;
    if (![firstScanner scanDouble:&first] || !firstScanner.isAtEnd ||
        ![secondScanner scanDouble:&second] || !secondScanner.isAtEnd) {
        return NO;
    }

    return LSCoordinateFromPair(first, second, coordinate);
}

static BOOL LSLooksLikeMapLink(NSString *query) {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    NSString *scheme = components.scheme.lowercaseString;
    NSString *host = components.host.lowercaseString;
    if (!([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) || host.length == 0) return NO;

    return [host isEqualToString:@"maps.app.goo.gl"] ||
           [host hasSuffix:@".google.com"] ||
           [host isEqualToString:@"google.com"] ||
           [host hasSuffix:@".goo.gl"] ||
           [host isEqualToString:@"goo.gl"] ||
           [host isEqualToString:@"maps.apple.com"];
}

static NSString *LSSearchTextFromMapURL(NSURL *url) {
    if (!url) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];

    NSArray<NSString *> *preferredKeys = @[@"query", @"q", @"destination", @"ll", @"center"];
    for (NSString *key in preferredKeys) {
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name caseInsensitiveCompare:key] != NSOrderedSame || item.value.length == 0) continue;
            NSString *value = LSNormalizeCoordinateSearchText(item.value);
            if (value.length) return value;
        }
    }

    NSString *path = [components.percentEncodedPath stringByRemovingPercentEncoding] ?: components.path;
    NSRange placeRange = [path rangeOfString:@"/place/" options:NSCaseInsensitiveSearch];
    if (placeRange.location != NSNotFound) {
        NSString *tail = [path substringFromIndex:NSMaxRange(placeRange)];
        NSString *place = [[tail componentsSeparatedByString:@"/"] firstObject];
        place = [[place stringByReplacingOccurrencesOfString:@"+" withString:@" "]
                 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (place.length) return place;
    }
    return nil;
}

@interface MapPickerViewController () <MKMapViewDelegate, UISearchBarDelegate, CLLocationManagerDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) UISwitch *locationSwitch;
@property (nonatomic, strong) UISwitch *fluctuationSwitch;
@property (nonatomic, strong) UIButton *radiusButton;
@property (nonatomic, strong) UISegmentedControl *mapTypeControl;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) CLLocationCoordinate2D selectedCoordinate;
@property (nonatomic, copy) NSString *selectedName;
@property (nonatomic, assign) BOOL fetchingRealLocation;
@end

@implementation MapPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.selectedCoordinate = [PersistenceManager shared].hasStoredCoordinate ? [PersistenceManager shared].spoofCoordinate : CLLocationCoordinate2DMake(24.7136, 46.6753);
    self.selectedName = @"الموقع المختار";
    [self buildInterface];
    [self updateFromPersistence];
    [self movePinToCoordinate:self.selectedCoordinate name:self.selectedName animated:NO];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [LSOverlayManager setMapPickerVisible:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    LSSetHooksBypassed(NO);
    [LSOverlayManager restoreMapPickerSessionState];
}

- (UIColor *)panelColor {
    return [UIColor colorWithRed:0.045 green:0.050 blue:0.065 alpha:0.99];
}

- (UIColor *)rowColor {
    return [UIColor colorWithRed:0.095 green:0.105 blue:0.135 alpha:1.0];
}

- (UIButton *)buttonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    button.backgroundColor = color;
    button.layer.cornerRadius = 11.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)rowWithIcon:(NSString *)iconName title:(NSString *)title tint:(UIColor *)tint accessory:(UIView *)accessory {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [self rowColor];
    row.layer.cornerRadius = 13.0;
    row.layer.cornerCurve = kCACornerCurveContinuous;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = tint;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:icon];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentLeft;
    [row addSubview:label];

    accessory.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:accessory];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:48.0],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:22.0],
        [icon.heightAnchor constraintEqualToConstant:22.0],
        [accessory.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14.0],
        [accessory.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintEqualToAnchor:accessory.leadingAnchor constant:-12.0],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:icon.trailingAnchor constant:10.0],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

- (void)buildInterface {
    self.panel = [[UIView alloc] init];
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    self.panel.backgroundColor = [self panelColor];
    self.panel.layer.cornerRadius = 30.0;
    self.panel.layer.cornerCurve = kCACornerCurveContinuous;
    self.panel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.40;
    self.panel.layer.shadowRadius = 24.0;
    self.panel.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    self.panel.layer.masksToBounds = NO;
    [self.view addSubview:self.panel];

    UIView *grabber = [[UIView alloc] init];
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    grabber.backgroundColor = [UIColor colorWithWhite:0.48 alpha:0.8];
    grabber.layer.cornerRadius = 2.5;
    [self.panel addSubview:grabber];

    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = [self rowColor];
    header.layer.cornerRadius = 17.0;
    header.layer.cornerCurve = kCACornerCurveContinuous;
    [self.panel addSubview:header];

    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"location.north.fill"]];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.tintColor = [UIColor colorWithRed:1.0 green:0.24 blue:0.28 alpha:1.0];
    [header addSubview:logo];

    UILabel *brand = [[UILabel alloc] init];
    brand.translatesAutoresizingMaskIntoConstraints = NO;
    brand.text = @"XsGpS";
    brand.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBlack];
    brand.textColor = UIColor.whiteColor;
    [header addSubview:brand];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.layer.cornerRadius = 14.0;
    self.statusLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusLabel.layer.masksToBounds = YES;
    [header addSubview:self.statusLabel];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    close.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
    close.layer.cornerRadius = 19.0;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];

    UIButton *identityGear = [UIButton buttonWithType:UIButtonTypeSystem];
    identityGear.translatesAutoresizingMaskIntoConstraints = NO;
    [identityGear setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    identityGear.tintColor = UIColor.whiteColor;
    identityGear.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    identityGear.layer.cornerRadius = 16.0;
    identityGear.accessibilityLabel = @"نقل هوية XsGpS";
    [identityGear addTarget:self action:@selector(identitySettingsTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:identityGear];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"اسم، إحداثيات، أو رابط خرائط";
    self.searchBar.tintColor = UIColor.whiteColor;
    self.searchBar.searchTextField.textColor = UIColor.whiteColor;
    self.searchBar.searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"اسم، إحداثيات، أو رابط خرائط"
                                                                                           attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.72]}];
    self.searchBar.searchTextField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    self.searchBar.searchTextField.layer.cornerRadius = 15.0;
    self.searchBar.searchTextField.layer.cornerCurve = kCACornerCurveContinuous;
    self.searchBar.searchTextField.clipsToBounds = YES;
    [self.panel addSubview:self.searchBar];

    UIButton *bookmarks = [self buttonWithTitle:@"المحفوظات  🔖" color:[UIColor colorWithRed:0.34 green:0.20 blue:0.04 alpha:1.0] action:@selector(bookmarksTapped)];
    UIButton *save = [self buttonWithTitle:@"حفظ  ✚" color:[UIColor colorWithRed:0.05 green:0.38 blue:0.16 alpha:1.0] action:@selector(saveTapped)];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[bookmarks, save]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.spacing = 9.0;
    buttons.distribution = UIStackViewDistributionFillEqually;
    [self.panel addSubview:buttons];

    self.mapView = [[MKMapView alloc] init];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.delegate = self;
    self.mapView.mapType = MKMapTypeStandard;
    self.mapView.showsUserLocation = NO;
    self.mapView.layer.cornerRadius = 20.0;
    self.mapView.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapView.clipsToBounds = YES;
    [self.panel addSubview:self.mapView];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapLongPressed:)];
    longPress.minimumPressDuration = 0.25;
    [self.mapView addGestureRecognizer:longPress];

    self.mapTypeControl = [[UISegmentedControl alloc] initWithItems:@[@"عادي", @"قمر صناعي"]];
    self.mapTypeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapTypeControl.selectedSegmentIndex = 0;
    self.mapTypeControl.selectedSegmentTintColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    NSDictionary *segmentText = @{NSForegroundColorAttributeName: UIColor.whiteColor,
                                  NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold]};
    [self.mapTypeControl setTitleTextAttributes:segmentText forState:UIControlStateNormal];
    [self.mapTypeControl setTitleTextAttributes:segmentText forState:UIControlStateSelected];
    [self.mapTypeControl addTarget:self action:@selector(mapTypeChanged) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.mapTypeControl];

    UIButton *myLocation = [self buttonWithTitle:@"موقعي  ➤" color:[UIColor colorWithRed:0.06 green:0.24 blue:0.45 alpha:1.0] action:@selector(myLocationTapped)];
    [self.panel addSubview:myLocation];

    self.locationSwitch = [[UISwitch alloc] init];
    [self.locationSwitch addTarget:self action:@selector(locationSwitchChanged) forControlEvents:UIControlEventValueChanged];
    UIView *locationRow = [self rowWithIcon:@"power" title:@"تفعيل الموقع" tint:[UIColor colorWithRed:0.20 green:0.90 blue:0.35 alpha:1.0] accessory:self.locationSwitch];
    [self.panel addSubview:locationRow];

    self.fluctuationSwitch = [[UISwitch alloc] init];
    [self.fluctuationSwitch addTarget:self action:@selector(fluctuationChanged) forControlEvents:UIControlEventValueChanged];
    self.radiusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.radiusButton setTitle:@"النطاق" forState:UIControlStateNormal];
    [self.radiusButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.radiusButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    self.radiusButton.backgroundColor = [UIColor colorWithRed:0.28 green:0.05 blue:0.30 alpha:1.0];
    self.radiusButton.layer.cornerRadius = 10.0;
    [self.radiusButton addTarget:self action:@selector(radiusTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *fluctuationAccessory = [[UIStackView alloc] initWithArrangedSubviews:@[self.radiusButton, self.fluctuationSwitch]];
    fluctuationAccessory.axis = UILayoutConstraintAxisHorizontal;
    fluctuationAccessory.spacing = 10.0;
    fluctuationAccessory.alignment = UIStackViewAlignmentCenter;
    UIView *fluctuationRow = [self rowWithIcon:@"shuffle" title:@"حركة عشوائية" tint:[UIColor colorWithRed:0.95 green:0.15 blue:0.95 alpha:1.0] accessory:fluctuationAccessory];
    [self.panel addSubview:fluctuationRow];

    [NSLayoutConstraint activateConstraints:@[
        [self.panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18.0],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18.0],
        [self.panel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14.0],
        [self.panel.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0],

        [grabber.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:7.0],
        [grabber.centerXAnchor constraintEqualToAnchor:self.panel.centerXAnchor],
        [grabber.widthAnchor constraintEqualToConstant:44.0],
        [grabber.heightAnchor constraintEqualToConstant:4.0],

        [header.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:9.0],
        [header.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [header.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [header.heightAnchor constraintEqualToConstant:54.0],

        [logo.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:17.0],
        [logo.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [logo.widthAnchor constraintEqualToConstant:27.0],
        [logo.heightAnchor constraintEqualToConstant:30.0],
        [brand.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:10.0],
        [brand.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-12.0],
        [close.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:34.0],
        [close.heightAnchor constraintEqualToConstant:34.0],

        [identityGear.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-6.0],
        [identityGear.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [identityGear.widthAnchor constraintEqualToConstant:32.0],
        [identityGear.heightAnchor constraintEqualToConstant:32.0],

        [self.statusLabel.trailingAnchor constraintEqualToAnchor:identityGear.leadingAnchor constant:-5.0],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.statusLabel.heightAnchor constraintEqualToConstant:28.0],
        [self.statusLabel.widthAnchor constraintEqualToConstant:72.0],
        [self.statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:brand.trailingAnchor constant:4.0],

        [self.searchBar.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:7.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [self.searchBar.heightAnchor constraintEqualToConstant:44.0],

        [buttons.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4.0],
        [buttons.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [buttons.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [buttons.heightAnchor constraintEqualToConstant:44.0],

        [self.mapView.topAnchor constraintEqualToAnchor:buttons.bottomAnchor constant:9.0],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [self.mapView.heightAnchor constraintEqualToConstant:300.0],

        [self.mapTypeControl.topAnchor constraintEqualToAnchor:self.mapView.bottomAnchor constant:8.0],
        [self.mapTypeControl.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [self.mapTypeControl.heightAnchor constraintEqualToConstant:36.0],
        [myLocation.topAnchor constraintEqualToAnchor:self.mapView.bottomAnchor constant:8.0],
        [myLocation.leadingAnchor constraintEqualToAnchor:self.mapTypeControl.trailingAnchor constant:10.0],
        [myLocation.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [myLocation.widthAnchor constraintEqualToAnchor:self.mapTypeControl.widthAnchor multiplier:0.85],
        [myLocation.heightAnchor constraintEqualToConstant:36.0],

        [locationRow.topAnchor constraintEqualToAnchor:self.mapTypeControl.bottomAnchor constant:8.0],
        [locationRow.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [locationRow.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],

        [fluctuationRow.topAnchor constraintEqualToAnchor:locationRow.bottomAnchor constant:8.0],
        [fluctuationRow.leadingAnchor constraintEqualToAnchor:locationRow.leadingAnchor],
        [fluctuationRow.trailingAnchor constraintEqualToAnchor:locationRow.trailingAnchor],

        [self.radiusButton.widthAnchor constraintEqualToConstant:68.0],
        [self.radiusButton.heightAnchor constraintEqualToConstant:31.0],

        [fluctuationRow.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-11.0],
    ]];

    // Allow the map to absorb extra height on taller phones while keeping a compact panel.
    [self.mapView setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
}

- (void)updateFromPersistence {
    PersistenceManager *store = [PersistenceManager shared];
    LSSmoothRandomMovementManager *smooth = [LSSmoothRandomMovementManager shared];
    self.locationSwitch.on = store.isSpoofingEnabled;
    self.fluctuationSwitch.on = smooth.isEnabled;
    NSString *radiusTitle = [NSString stringWithFormat:@"%.0fm", MAX(1.0, smooth.radius)];
    [self.radiusButton setTitle:radiusTitle forState:UIControlStateNormal];
    [self updateStatus];
}

- (void)updateStatus {
    BOOL enabled = [PersistenceManager shared].isSpoofingEnabled && [LSActivationManager shared].isActivated;
    self.statusLabel.text = enabled ? @"✓ مفعل" : @"✕ متوقف";
    self.statusLabel.textColor = enabled ? [UIColor colorWithRed:0.35 green:1.0 blue:0.52 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.34 blue:0.38 alpha:1.0];
    self.statusLabel.backgroundColor = enabled ? [UIColor colorWithRed:0.02 green:0.30 blue:0.12 alpha:0.55] : [UIColor colorWithRed:0.35 green:0.03 blue:0.07 alpha:0.58];
}

- (void)movePinToCoordinate:(CLLocationCoordinate2D)coordinate name:(NSString *)name animated:(BOOL)animated {
    self.selectedCoordinate = coordinate;
    self.selectedName = name.length ? name : @"الموقع المختار";
    if (self.pin) [self.mapView removeAnnotation:self.pin];
    self.pin = [[MKPointAnnotation alloc] init];
    self.pin.coordinate = coordinate;
    self.pin.title = @"الموقع المختار";
    self.pin.subtitle = self.selectedName;
    [self.mapView addAnnotation:self.pin];
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 1200.0, 1200.0);
    [self.mapView setRegion:region animated:animated];
}

- (void)mapLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];
    [self movePinToCoordinate:coordinate name:@"الموقع المختار" animated:YES];
    [[LSSmoothRandomMovementManager shared] resetAnchorToCoordinate:coordinate];
    if (self.locationSwitch.isOn) {
        [[PersistenceManager shared] setSpoofCoordinate:coordinate enabled:YES];
    } else {
        [[PersistenceManager shared] setSpoofCoordinate:coordinate enabled:NO];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = [searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) return;

    CLLocationCoordinate2D coordinate = kCLLocationCoordinate2DInvalid;
    if (LSParseCoordinateSearchQuery(query, &coordinate)) {
        [self applySearchCoordinate:coordinate];
        return;
    }

    if (LSLooksLikeMapLink(query)) {
        [self resolveMapLinkAndSearch:query];
        return;
    }

    [self performPlaceSearchForQuery:query preferCurrentRegion:YES];
}

- (void)applySearchCoordinate:(CLLocationCoordinate2D)coordinate {
    NSString *coordinateName = [NSString stringWithFormat:@"%.7f, %.7f", coordinate.latitude, coordinate.longitude];
    self.searchBar.text = coordinateName;
    [self movePinToCoordinate:coordinate name:coordinateName animated:YES];
    [[LSSmoothRandomMovementManager shared] resetAnchorToCoordinate:coordinate];
}

- (void)resolveMapLinkAndSearch:(NSString *)linkText {
    NSURL *url = [NSURL URLWithString:[linkText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    if (!url) {
        [self performPlaceSearchForQuery:linkText preferCurrentRegion:YES];
        return;
    }

    // Full links can contain a readable query/place name even when they do not contain coordinates.
    NSString *directText = LSSearchTextFromMapURL(url);
    CLLocationCoordinate2D directCoordinate = kCLLocationCoordinate2DInvalid;
    if (directText.length && LSParseCoordinateSearchQuery(directText, &directCoordinate)) {
        [self applySearchCoordinate:directCoordinate];
        return;
    }

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 10.0;
    configuration.timeoutIntervalForResource = 12.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)data;
        NSURL *resolvedURL = response.URL ?: url;
        NSString *resolvedText = resolvedURL.absoluteString ?: linkText;

        CLLocationCoordinate2D coordinate = kCLLocationCoordinate2DInvalid;
        BOOL foundCoordinate = LSParseCoordinateSearchQuery(resolvedText, &coordinate);
        NSString *placeText = foundCoordinate ? nil : LSSearchTextFromMapURL(resolvedURL);
        if (!placeText.length && !foundCoordinate) placeText = directText;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (foundCoordinate) {
                [self applySearchCoordinate:coordinate];
                return;
            }

            if (placeText.length) {
                [self performPlaceSearchForQuery:placeText preferCurrentRegion:NO];
                return;
            }

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعذر فتح رابط الخريطة"
                                                                               message:@"تأكد من اتصال الإنترنت وصحة رابط Google Maps ثم حاول مرة ثانية."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                return;
            }

            [self performPlaceSearchForQuery:resolvedText preferCurrentRegion:NO];
        });
        [session finishTasksAndInvalidate];
    }];
    [task resume];
}

- (void)performPlaceSearchForQuery:(NSString *)query preferCurrentRegion:(BOOL)preferCurrentRegion {
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    if (preferCurrentRegion) {
        request.region = self.mapView.region;
    }

    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        MKMapItem *item = response.mapItems.firstObject;
        if (!error && item && CLLocationCoordinate2DIsValid(item.placemark.coordinate)) {
            NSString *name = item.name.length ? item.name : query;
            self.searchBar.text = name;
            [self movePinToCoordinate:item.placemark.coordinate name:name animated:YES];
            [[LSSmoothRandomMovementManager shared] resetAnchorToCoordinate:item.placemark.coordinate];
            return;
        }

        // A map-region hint can be too restrictive for a distant city/place.
        // Retry once globally before declaring that no place was found.
        if (preferCurrentRegion) {
            [self performPlaceSearchForQuery:query preferCurrentRegion:NO];
            return;
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"لم يتم العثور على الموقع"
                                                                       message:@"جرّب اسمًا أو عنوانًا أو إحداثيات مثل: (21.1932564, 42.7134373)"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)locationSwitchChanged {
    PersistenceManager *store = [PersistenceManager shared];
    if (self.locationSwitch.isOn) {
        if (![LSActivationManager shared].isActivated) {
            self.locationSwitch.on = NO;
            [self updateStatus];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"XsGpS" message:@"التفعيل غير صالح. أغلق الواجهة وافتحها من جديد لإدخال كود التفعيل." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        [[LSSmoothRandomMovementManager shared] resetAnchorToCoordinate:self.selectedCoordinate];
        [store setSpoofCoordinate:self.selectedCoordinate enabled:YES];
    } else {
        [store setSpoofCoordinate:self.selectedCoordinate enabled:NO];
    }
    [self updateStatus];
}

- (void)fluctuationChanged {
    [[LSSmoothRandomMovementManager shared] setEnabled:self.fluctuationSwitch.isOn
                                      anchorCoordinate:self.selectedCoordinate];
}

- (void)radiusTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"نطاق الحركة العشوائية" message:@"أدخل نصف القطر بالمتر" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%.0f", [LSSmoothRandomMovementManager shared].radius];
        field.textAlignment = NSTextAlignmentCenter;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        double radius = MAX(1.0, MIN(5000.0, alert.textFields.firstObject.text.doubleValue));
        [LSSmoothRandomMovementManager shared].radius = radius;
        [weakSelf.radiusButton setTitle:[NSString stringWithFormat:@"%.0fm", radius] forState:UIControlStateNormal];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حفظ الموقع" message:@"اكتب اسمًا للموقع" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = self.selectedName.length ? self.selectedName : @"موقع محفوظ";
        field.textAlignment = NSTextAlignmentRight;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text.length ? alert.textFields.firstObject.text : @"موقع محفوظ";
        [[BookmarksManager shared] addBookmarkWithName:name coordinate:weakSelf.selectedCoordinate];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)bookmarksTapped {
    NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"المحفوظات" message:bookmarks.count ? @"اختر موقعًا" : @"لا توجد مواقع محفوظة" preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (LSBookmark *bookmark in bookmarks) {
        [alert addAction:[UIAlertAction actionWithTitle:bookmark.name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf movePinToCoordinate:bookmark.coordinate name:bookmark.name animated:YES];
            [[LSSmoothRandomMovementManager shared] resetAnchorToCoordinate:bookmark.coordinate];
            [[PersistenceManager shared] setSpoofCoordinate:bookmark.coordinate enabled:NO];
            weakSelf.locationSwitch.on = NO;
            [weakSelf updateStatus];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.panel;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.panel.bounds), 90, 1, 1);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)mapTypeChanged {
    self.mapView.mapType = self.mapTypeControl.selectedSegmentIndex == 1 ? MKMapTypeSatellite : MKMapTypeStandard;
}

- (void)myLocationTapped {
    self.fetchingRealLocation = YES;
    LSSetHooksBypassed(YES);
    if (!self.locationManager) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
        self.locationManager.distanceFilter = kCLDistanceFilterNone;
    }
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) status = self.locationManager.authorizationStatus;
    else status = CLLocationManager.authorizationStatus;
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        self.fetchingRealLocation = NO;
        LSSetHooksBypassed(NO);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"الموقع" message:@"فعّل إذن الموقع للتطبيق ثم جرّب مرة ثانية." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (status == kCLAuthorizationStatusNotDetermined) { [self.locationManager requestWhenInUseAuthorization]; return; }
    [self beginFastRealLocationLookup];
}

- (void)beginFastRealLocationLookup {
    if (!self.fetchingRealLocation) return;
    CLLocation *cached = self.locationManager.location;
    if (cached && cached.horizontalAccuracy >= 0.0 && fabs(cached.timestamp.timeIntervalSinceNow) < 20.0) {
        [self finishRealLocationLookupWithLocation:cached];
        return;
    }
    [self.locationManager startUpdatingLocation];
    [self.locationManager requestLocation];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.fetchingRealLocation) return;
        CLLocation *fallback = self.locationManager.location;
        if (fallback && fallback.horizontalAccuracy >= 0.0) [self finishRealLocationLookupWithLocation:fallback];
    });
}

- (void)finishRealLocationLookupWithLocation:(CLLocation *)location {
    if (!self.fetchingRealLocation) return;
    self.fetchingRealLocation = NO;
    [self.locationManager stopUpdatingLocation];
    LSSetHooksBypassed(NO);
    if (!location) return;
    [self movePinToCoordinate:location.coordinate name:@"موقعي الحقيقي" animated:YES];
    [[LSSmoothRandomMovementManager shared] resetAnchorToCoordinate:location.coordinate];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    (void)manager;
    if (!self.fetchingRealLocation) return;
    CLLocation *best = nil;
    for (CLLocation *candidate in [locations reverseObjectEnumerator]) {
        if (candidate.horizontalAccuracy >= 0.0) { best = candidate; break; }
    }
    if (best) [self finishRealLocationLookupWithLocation:best];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager;
    if (!self.fetchingRealLocation) return;
    if (error.code == kCLErrorLocationUnknown) return;
    self.fetchingRealLocation = NO;
    [self.locationManager stopUpdatingLocation];
    LSSetHooksBypassed(NO);
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (!self.fetchingRealLocation) return;
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) [self beginFastRealLocationLookup];
    else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) { self.fetchingRealLocation = NO; LSSetHooksBypassed(NO); }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    (void)manager;
    if (@available(iOS 14.0, *)) return;
    if (!self.fetchingRealLocation) return;
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) [self beginFastRealLocationLookup];
    else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) { self.fetchingRealLocation = NO; LSSetHooksBypassed(NO); }
}

- (void)identitySettingsTapped {
    NSString *uuid = [LSActivationManager shared].installationUUID;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"نقل هوية XsGpS"
                                                                  message:[LSIdentityTransferBundle identitySummaryWithUUID:uuid]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"نسخ حزمة النقل" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self prepareIdentityTransfer];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"كتابة حزمة النقل" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self confirmIdentityImport];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    if (menu.popoverPresentationController) {
        menu.popoverPresentationController.sourceView = self.panel;
        menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.panel.bounds), 38.0, 1.0, 1.0);
    }
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)showIdentityMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"XsGpS" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)prepareIdentityTransfer {
    [[LSActivationManager shared] prepareIdentityTransferWithCompletion:^(BOOL success, NSString *message, NSString *transferCode) {
        if (!success || !transferCode.length) {
            [self showIdentityMessage:message];
            return;
        }
        NSString *uuid = [LSActivationManager shared].installationUUID;
        NSString *transferText = [LSIdentityTransferBundle exportTextWithUUID:uuid transferCode:transferCode];
        NSString *supported = [LSIdentityTransferBundle supportedHostLocalIdentifier];
        NSString *hostNote = supported ? @"معرّف التطبيق المحلي fc_uuidForDevice: مشمول في الحزمة."
                                       : @"لا يوجد معرّف تطبيق محلي fc_uuidForDevice مدعوم في هذه النسخة.";
        NSString *details = [NSString stringWithFormat:@"تشمل الحزمة هوية XsGpS وتفعيلها وإعداداتها.\n\n%@\n\nIDFV الأصلي مُدرج للرجوع إليه فقط، ولن يتغير على الآيفون الجديد.\n\nصالحة لمدة ١٠ دقائق ولمرة واحدة.", hostNote];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حزمة نقل هوية XsGpS" message:details preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"نسخ الحزمة كاملة" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = transferText;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)confirmIdentityImport {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"استيراد هوية سابقة"
                                                                 message:@"استيراد الحزمة يستعيد تفعيل وإعدادات XsGpS بعد التحقق. يحتفظ الآيفون الجديد بهويته الأصلية."
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"متابعة" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self promptIdentityImport];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptIdentityImport {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"كتابة معرف التطبيق"
                                                                 message:@"الصق حزمة النقل في الحقل الأول. يمكنك أيضًا إدخال UUID ورمز النقل القديمين."
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"حزمة النقل أو UUID القديم";
        field.textAlignment = NSTextAlignmentLeft;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"رمز النقل المؤقت";
        field.textAlignment = NSTextAlignmentLeft;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"استعادة" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSDictionary<NSString *, NSString *> *record =
            [LSIdentityTransferBundle parseText:alert.textFields.firstObject.text
                            separateTransferCode:alert.textFields.lastObject.text];
        if (!record) {
            [self showIdentityMessage:@"حزمة النقل غير صحيحة أو ناقصة."];
            return;
        }
        NSString *hostError = [LSIdentityTransferBundle hostIdentityImportErrorForRecord:record];
        if (hostError) {
            [self showIdentityMessage:hostError];
            return;
        }
        [[LSActivationManager shared] completeIdentityTransferFromUUID:record[@"uuid"] transferCode:record[@"token"] completion:^(BOOL success, NSString *message) {
            NSString *result = message;
            if (success && record[@"host_local_uuid"]) {
                BOOL applied = [LSIdentityTransferBundle restoreVerifiedHostLocalIdentifierFromRecord:record];
                result = [message stringByAppendingString:applied
                    ? @"\nتم استعادة UUID المحلي للتطبيق. أغلق التطبيق وافتحه لتحديث أي ذاكرة مؤقتة."
                    : @"\nتعذرت استعادة UUID المحلي للتطبيق؛ استعيدت هوية XsGpS فقط."];
            }
            if (success) {
                PersistenceManager *prefs = [PersistenceManager shared];
                CLLocationCoordinate2D coordinate = prefs.hasStoredCoordinate ? prefs.spoofCoordinate : self.selectedCoordinate;
                [[LSSmoothRandomMovementManager shared] resetAnchorToCoordinate:coordinate];
                [self movePinToCoordinate:coordinate name:@"الموقع المستعاد" animated:YES];
                [self updateFromPersistence];
            }
            [self showIdentityMessage:result];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
