#import "LocationSpoofer.h"
#import "PersistenceManager.h"
#import "OverlayWindow.h"
#import "LSActivationManager.h"
#import "LSSmoothRandomMovementManager.h"

__attribute__((constructor(101)))
static void XsGpSDylibInit(void) {
    [PersistenceManager loadEarly];
    [[LSActivationManager shared] warmUp];
    [[LSSmoothRandomMovementManager shared] restoreIfNeeded];
    [LocationSpoofer installHooks];

    dispatch_async(dispatch_get_main_queue(), ^{
        [LSOverlayManager install];
    });
}
