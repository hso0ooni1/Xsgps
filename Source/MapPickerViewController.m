#import "MapPickerViewController.h"
#import "PersistenceManager.h"
#import "BookmarksManager.h"
#import "LocationSpoofer.h"
#import "LSActivationManager.h"
#import "OverlayWindow.h"

#import <MapKit/MapKit.h>

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
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.58];
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
    button.titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
    button.backgroundColor = color;
    button.layer.cornerRadius = 13.0;
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
    label.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightBold];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentRight;
    [row addSubview:label];

    accessory.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:accessory];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:57.0],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:25.0],
        [icon.heightAnchor constraintEqualToConstant:25.0],
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
    brand.font = [UIFont systemFontOfSize:25 weight:UIFontWeightBlack];
    brand.textColor = UIColor.whiteColor;
    [header addSubview:brand];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
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

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"عنوان، إحداثيات، أو عنوان وطني";
    self.searchBar.tintColor = UIColor.whiteColor;
    self.searchBar.searchTextField.textColor = UIColor.whiteColor;
    self.searchBar.searchTextField.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    self.searchBar.searchTextField.layer.cornerRadius = 15.0;
    self.searchBar.searchTextField.layer.cornerCurve = kCACornerCurveContinuous;
    self.searchBar.searchTextField.clipsToBounds = YES;
    [self.panel addSubview:self.searchBar];

    UIButton *bookmarks = [self buttonWithTitle:@"المحفوظات  🔖" color:[UIColor colorWithRed:0.34 green:0.20 blue:0.04 alpha:1.0] action:@selector(bookmarksTapped)];
    UIButton *save = [self buttonWithTitle:@"حفظ  ✚" color:[UIColor colorWithRed:0.05 green:0.38 blue:0.16 alpha:1.0] action:@selector(saveTapped)];
    UIButton *restore = [self buttonWithTitle:@"استعادة  ◉" color:[UIColor colorWithRed:0.46 green:0.08 blue:0.11 alpha:1.0] action:@selector(restoreTapped)];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[bookmarks, save, restore]];
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
    [self.mapTypeControl addTarget:self action:@selector(mapTypeChanged) forControlEvents:UIControlEventValueChanged];
    [self.panel addSubview:self.mapTypeControl];

    UIButton *myLocation = [self buttonWithTitle:@"موقعي  ➤" color:[UIColor colorWithRed:0.06 green:0.24 blue:0.45 alpha:1.0] action:@selector(myLocationTapped)];
    [self.panel addSubview:myLocation];

    self.locationSwitch = [[UISwitch alloc] init];
    [self.locationSwitch addTarget:self action:@selector(locationSwitchChanged) forControlEvents:UIControlEventValueChanged];
    UIView *locationRow = [self rowWithIcon:@"power" title:@"تفعيل تغيير الموقع" tint:[UIColor colorWithRed:0.20 green:0.90 blue:0.35 alpha:1.0] accessory:self.locationSwitch];
    [self.panel addSubview:locationRow];

    self.fluctuationSwitch = [[UISwitch alloc] init];
    [self.fluctuationSwitch addTarget:self action:@selector(fluctuationChanged) forControlEvents:UIControlEventValueChanged];
    self.radiusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.radiusButton setTitle:@"النطاق" forState:UIControlStateNormal];
    [self.radiusButton setTitleColor:[UIColor colorWithRed:0.95 green:0.25 blue:0.95 alpha:1.0] forState:UIControlStateNormal];
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

    UIButton *copyDevice = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyDevice setTitle:@"نسخ" forState:UIControlStateNormal];
    [copyDevice setTitleColor:[UIColor colorWithRed:1.0 green:0.55 blue:0.20 alpha:1.0] forState:UIControlStateNormal];
    copyDevice.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    copyDevice.backgroundColor = [UIColor colorWithRed:0.28 green:0.14 blue:0.04 alpha:1.0];
    copyDevice.layer.cornerRadius = 10.0;
    [copyDevice addTarget:self action:@selector(copyDeviceID) forControlEvents:UIControlEventTouchUpInside];
    UIView *deviceRow = [self rowWithIcon:@"iphone" title:@"معرف الجهاز" tint:[UIColor colorWithRed:1.0 green:0.50 blue:0.16 alpha:1.0] accessory:copyDevice];
    [self.panel addSubview:deviceRow];

    [NSLayoutConstraint activateConstraints:@[
        [self.panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18.0],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18.0],
        [self.panel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        [self.panel.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0],

        [grabber.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:8.0],
        [grabber.centerXAnchor constraintEqualToAnchor:self.panel.centerXAnchor],
        [grabber.widthAnchor constraintEqualToConstant:52.0],
        [grabber.heightAnchor constraintEqualToConstant:5.0],

        [header.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:14.0],
        [header.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [header.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [header.heightAnchor constraintEqualToConstant:64.0],

        [logo.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:17.0],
        [logo.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [logo.widthAnchor constraintEqualToConstant:32.0],
        [logo.heightAnchor constraintEqualToConstant:36.0],
        [brand.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:10.0],
        [brand.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-12.0],
        [close.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:38.0],
        [close.heightAnchor constraintEqualToConstant:38.0],

        [self.statusLabel.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-10.0],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.statusLabel.heightAnchor constraintEqualToConstant:32.0],
        [self.statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:142.0],
        [self.statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:brand.trailingAnchor constant:8.0],

        [self.searchBar.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:7.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [self.searchBar.heightAnchor constraintEqualToConstant:52.0],

        [buttons.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4.0],
        [buttons.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [buttons.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [buttons.heightAnchor constraintEqualToConstant:52.0],

        [self.mapView.topAnchor constraintEqualToAnchor:buttons.bottomAnchor constant:9.0],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [self.mapView.heightAnchor constraintEqualToConstant:300.0],

        [self.mapTypeControl.topAnchor constraintEqualToAnchor:self.mapView.bottomAnchor constant:8.0],
        [self.mapTypeControl.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [self.mapTypeControl.heightAnchor constraintEqualToConstant:42.0],
        [myLocation.topAnchor constraintEqualToAnchor:self.mapView.bottomAnchor constant:8.0],
        [myLocation.leadingAnchor constraintEqualToAnchor:self.mapTypeControl.trailingAnchor constant:10.0],
        [myLocation.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],
        [myLocation.widthAnchor constraintEqualToAnchor:self.mapTypeControl.widthAnchor multiplier:0.85],
        [myLocation.heightAnchor constraintEqualToConstant:42.0],

        [locationRow.topAnchor constraintEqualToAnchor:self.mapTypeControl.bottomAnchor constant:8.0],
        [locationRow.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14.0],
        [locationRow.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-14.0],

        [fluctuationRow.topAnchor constraintEqualToAnchor:locationRow.bottomAnchor constant:8.0],
        [fluctuationRow.leadingAnchor constraintEqualToAnchor:locationRow.leadingAnchor],
        [fluctuationRow.trailingAnchor constraintEqualToAnchor:locationRow.trailingAnchor],

        [self.radiusButton.widthAnchor constraintEqualToConstant:76.0],
        [self.radiusButton.heightAnchor constraintEqualToConstant:36.0],

        [deviceRow.topAnchor constraintEqualToAnchor:fluctuationRow.bottomAnchor constant:8.0],
        [deviceRow.leadingAnchor constraintEqualToAnchor:locationRow.leadingAnchor],
        [deviceRow.trailingAnchor constraintEqualToAnchor:locationRow.trailingAnchor],
        [deviceRow.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-14.0],

        [copyDevice.widthAnchor constraintEqualToConstant:68.0],
        [copyDevice.heightAnchor constraintEqualToConstant:36.0],
    ]];

    // Allow the map to absorb extra height on taller phones while keeping a compact panel.
    [self.mapView setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
}

- (void)updateFromPersistence {
    PersistenceManager *store = [PersistenceManager shared];
    self.locationSwitch.on = store.isSpoofingEnabled;
    self.fluctuationSwitch.on = store.fluctuationEnabled;
    NSString *radiusTitle = [NSString stringWithFormat:@"%.0fm", MAX(1.0, store.fluctuationRadius)];
    [self.radiusButton setTitle:radiusTitle forState:UIControlStateNormal];
    [self updateStatus];
}

- (void)updateStatus {
    BOOL enabled = [PersistenceManager shared].isSpoofingEnabled && [LSActivationManager shared].isActivated;
    self.statusLabel.text = enabled ? @"✓ تغيير الموقع مفعل" : @"✕ تغيير الموقع غير مفعل";
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

    NSArray<NSString *> *parts = [query componentsSeparatedByString:@","];
    if (parts.count == 2) {
        double lat = [parts[0] doubleValue];
        double lon = [parts[1] doubleValue];
        if (lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0) {
            [self movePinToCoordinate:CLLocationCoordinate2DMake(lat, lon) name:query animated:YES];
            return;
        }
    }

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    request.region = self.mapView.region;
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        MKMapItem *item = response.mapItems.firstObject;
        if (!self || error || !item) return;
        NSString *name = item.name ?: query;
        self.searchBar.text = name;
        [self movePinToCoordinate:item.placemark.coordinate name:name animated:YES];
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
        [store setSpoofCoordinate:self.selectedCoordinate enabled:YES];
    } else {
        [store setSpoofCoordinate:self.selectedCoordinate enabled:NO];
    }
    [self updateStatus];
}

- (void)fluctuationChanged {
    [PersistenceManager shared].fluctuationEnabled = self.fluctuationSwitch.isOn;
}

- (void)radiusTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"نطاق الحركة العشوائية" message:@"أدخل نصف القطر بالمتر" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%.0f", [PersistenceManager shared].fluctuationRadius];
        field.textAlignment = NSTextAlignmentCenter;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        double radius = MAX(1.0, MIN(5000.0, alert.textFields.firstObject.text.doubleValue));
        [PersistenceManager shared].fluctuationRadius = radius;
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

- (void)restoreTapped {
    PersistenceManager *store = [PersistenceManager shared];
    if (store.hasStoredCoordinate) {
        [self movePinToCoordinate:store.spoofCoordinate name:@"آخر موقع محفوظ" animated:YES];
        [store setSpoofCoordinate:store.spoofCoordinate enabled:NO];
        self.locationSwitch.on = NO;
        [self updateStatus];
    }
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
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    }
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) status = self.locationManager.authorizationStatus;
    else status = CLLocationManager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    [self.locationManager requestLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (!self.fetchingRealLocation) return;
    self.fetchingRealLocation = NO;
    CLLocation *location = locations.lastObject;
    LSSetHooksBypassed(NO);
    if (location) {
        [self movePinToCoordinate:location.coordinate name:@"موقعي الحقيقي" animated:YES];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager; (void)error;
    self.fetchingRealLocation = NO;
    LSSetHooksBypassed(NO);
}

- (void)copyDeviceID {
    UIPasteboard.generalPasteboard.string = [LSActivationManager shared].deviceID;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تم النسخ" message:@"تم نسخ معرف الجهاز" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
