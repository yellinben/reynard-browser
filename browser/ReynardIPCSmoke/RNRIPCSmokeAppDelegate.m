#import "RNRIPCSmokeAppDelegate.h"

#import "RNRIPCSmokeViewController.h"

@implementation RNRIPCSmokeAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    (void)application;
    (void)launchOptions;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    RNRIPCSmokeViewController *viewController = [[RNRIPCSmokeViewController alloc] init];
    self.window.rootViewController = [[UINavigationController alloc]
        initWithRootViewController:viewController];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
