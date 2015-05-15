//
//  Communicator.h
//  Prototype
//
//  Created by Timothy Rodney Nugent on 17/04/2015.
//  Copyright (c) 2015 Timothy Rodney Nugent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PNImports.h"
@import CoreLocation;

#define APP_DELEGATE ((AppDelegate *)[[UIApplication sharedApplication] delegate])
#define COMMUNICATOR [Communicator sharedCommunicator]

@class Communicator;
@protocol CommunicatorDelegate <NSObject>

@optional

- (void)communicator:(Communicator *)communicator didReceiveLocation:(CLLocation *)location fromPerson:(NSString *)person;
- (void)communicator:(Communicator *)communicator numberOfPeopleInGroupChanged:(NSArray *)people;
- (void)communicator:(Communicator *)communicator didUpdateHeading:(CLHeading *)heading;
- (void)communicator:(Communicator *)communicator personDidLeave:(NSString *)person;

@end

@interface Communicator : NSObject

@property (weak,nonatomic) id<CommunicatorDelegate> delegate;
@property (nonatomic, strong) NSString *person;

+ (Communicator *)sharedCommunicator;
- (void)connectToNetwork;
- (void)stopTracking;
- (void)addPersonToGroup:(NSString *)personName;
- (void)sendLocation:(CLLocation *)location;
- (void)sendLocation:(CLLocation *)location fromPerson:(NSString *)person;

- (void)testLocation:(BOOL)test;

@end
