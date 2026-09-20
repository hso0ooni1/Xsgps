#import "LocationSpoofer.h"
#import "PersistenceManager.h"
#import "OverlayWindow.h"
#import "LSActivationManager.h"

__attribute__((constructor(101)))
static void XsGpSDylibInit(void) {
    [PersistenceManager loadEarly];
    [[LSActivationManager shared] warmUp];
    [LocationSpoofer installHooks];

    dispatch_async(dispatch_get_main_queue(), ^{
        [LSOverlayManager install];
    });
}
