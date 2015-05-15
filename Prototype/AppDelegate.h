//
//  AppDelegate.h
//  Prototype
//
//  Created by Timothy Rodney Nugent on 17/04/2015.
//  Copyright (c) 2015 Timothy Rodney Nugent. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PNImports.h"

#define APP_DELEGATE ((AppDelegate *)[[UIApplication sharedApplication] delegate])

@interface AppDelegate : UIResponder <UIApplicationDelegate, PNDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) PNChannel *channel;

@end

