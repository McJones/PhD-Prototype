//
//  Communicator.m
//  Prototype
//
//  Created by Timothy Rodney Nugent on 17/04/2015.
//  Copyright (c) 2015 Timothy Rodney Nugent. All rights reserved.
//

#import "Communicator.h"

static Communicator *_sharedCommunicator;

@interface Communicator ()<PNDelegate,CLLocationManagerDelegate>
{
    BOOL debug;
}

@property (nonatomic, strong) PNChannel *channel;
@property (nonatomic, strong) NSMutableArray *people;
@property (strong, nonatomic) CLLocationManager *manager;
@property (strong, nonatomic) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray *locations;

@end

@implementation Communicator

+ (Communicator *)sharedCommunicator
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedCommunicator = [[Communicator alloc] init];
    });
    return _sharedCommunicator;
}

- (void)connectToNetwork
{
    [PubNub setDelegate:self];
    PNConfiguration *myConfig = [PNConfiguration configurationForOrigin:@"pubsub.pubnub.com"
                                                             publishKey:@"pub-c-32d8b3cf-da23-4d59-926a-f38f3376f743"
                                                           subscribeKey:@"sub-c-5945aaf4-e4b0-11e4-aa7e-0619f8945a4f"
                                                              secretKey:@"sec-c-ZGIyZjExMjEtNmEyZS00NTYzLWI2NzUtY2JiZjdhZDFkZGJi"];
    [PubNub setConfiguration:myConfig];
    [PubNub connect];
    self.channel = [PNChannel channelWithName:@"channel" shouldObservePresence:YES];
    [PubNub subscribeOn:@[self.channel]];
    
    self.people = [NSMutableArray array];
    debug = NO;
    
    // configuring the location manager
    if ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusDenied || [CLLocationManager authorizationStatus] != kCLAuthorizationStatusRestricted)
    {
        self.manager = [[CLLocationManager alloc] init];
        self.manager.delegate = self;
        
        if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined)
        {
            [self.manager requestAlwaysAuthorization];
        }
        if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorizedAlways)
        {
            self.manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
            //self.manager.headingFilter = kCLHeadingFilterNone;
            
            if ([CLLocationManager headingAvailable])
            {
                [self.manager startUpdatingHeading];
            }
            if ([CLLocationManager locationServicesEnabled])
            {
                [self.manager startUpdatingLocation];
            }
        }
    }
    self.locations = [NSMutableArray new];
}
- (void)stopTracking
{
    // turn off the manager
    [self.manager stopUpdatingHeading];
    [self.manager stopUpdatingLocation];
    // disconnect from pubnub
    [PubNub unsubscribeFrom:@[self.channel]];
    [PubNub disconnect];
    
    NSError *error;
    NSData *json = [NSJSONSerialization dataWithJSONObject:self.locations options:NSJSONWritingPrettyPrinted error:&error];
    if (error == nil)
    {
        NSDateFormatter *dateformatter = [NSDateFormatter new];
        [dateformatter setDateFormat:@"HH-mm-ss"];
        NSString *date = [dateformatter stringFromDate:[NSDate date]];
        
        // dump the json somewhere
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true);
        NSString *path = paths[0];
        NSString *name = [NSString stringWithFormat:@"%@-%@.json",self.person,date];
        path = [path stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] createFileAtPath:path contents:json attributes:nil];
    }
}

- (void)testLocation:(BOOL)test
{
    if (test)
    {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(sendTestLocations:) userInfo:nil repeats:YES];
        [self.timer fire];
    }
    else
    {
        [self.timer invalidate];
    }
}
- (void)sendTestLocations:(NSTimer *)timer
{
    [self sendYBLocation:timer];
    [self sendNorthLocation:timer];
    [self sendSouthLocation:timer];
}
- (void)sendYBLocation:(NSTimer *)timer
{
    NSLog(@"Firing YB");
    CGFloat targetLat = -42.883143;
    CGFloat targetLon = 147.327478;
    
    CLLocation *yellowBernard = [[CLLocation alloc] initWithLatitude:targetLat longitude:targetLon];
    [COMMUNICATOR sendLocation:yellowBernard fromPerson:@"Yellow Bernard"];
}
- (void)sendNorthLocation:(NSTimer *)timer
{
    NSLog(@"Firing North");
    CGFloat targetLat = -40.0;
    CGFloat targetLon = 140.0;
    
    CLLocation *yellowBernard = [[CLLocation alloc] initWithLatitude:targetLat longitude:targetLon];
    [COMMUNICATOR sendLocation:yellowBernard fromPerson:@"North"];
}
- (void)sendSouthLocation:(NSTimer *)timer
{
    NSLog(@"Firing South");
    CGFloat targetLat = -44.0;
    CGFloat targetLon = 140.0;
    
    CLLocation *yellowBernard = [[CLLocation alloc] initWithLatitude:targetLat longitude:targetLon];
    [COMMUNICATOR sendLocation:yellowBernard fromPerson:@"South"];
}

- (void)sendLocation:(CLLocation *)location
{
    [self sendLocation:location fromPerson:self.person];
}
- (void)sendLocation:(CLLocation *)location fromPerson:(NSString *)person
{
    NSNumber *lat = [NSNumber numberWithDouble:location.coordinate.latitude];
    NSNumber *lon = [NSNumber numberWithDouble:location.coordinate.longitude];
    NSDictionary *messageDict = @{@"key": @1,
                                  @"person": person,
                                  @"lon": lon,
                                  @"lat": lat};
    [PubNub sendMessage:messageDict toChannel:self.channel];
}

- (void)addPersonToGroup:(NSString *)personName
{
    self.person = personName;

    // tell the channel about it
    NSDictionary *messageInfo = @{@"key":@2,@"person":self.person};
    [PubNub sendMessage:messageInfo toChannel:self.channel];
}

#pragma mark - LocationManager delegates
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    CLLocation *location = locations.lastObject;
    [self sendLocation:location];
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(communicator:didReceiveLocation:fromPerson:)])
    {
        [self.delegate communicator:self didReceiveLocation:location fromPerson:self.person];
    }
    
    NSNumber *lat = [NSNumber numberWithDouble:location.coordinate.latitude];
    NSNumber *lon = [NSNumber numberWithDouble:location.coordinate.longitude];
    NSDictionary *locationDictionary = @{@"latitude":lat, @"longitude":lon};
    [self.locations addObject:locationDictionary];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(communicator:didUpdateHeading:)])
    {
        [self.delegate communicator:self didUpdateHeading:newHeading];
    }
}

- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager
{
    return YES;
}

#pragma mark - PubNub delegates
- (void)pubnubClient:(PubNub *)client didReceiveMessage:(PNMessage *)message
{
    if (debug)
        NSLog(@"%@",message.message);
    
    NSDictionary *messageInfo = message.message;
    if ([messageInfo[@"key"] isEqualToNumber: @1])
    {
        // they are sending a location
        if (![self.person isEqualToString:messageInfo[@"person"]])
        {
            NSNumber *lat = messageInfo[@"lat"];
            NSNumber *lon = messageInfo[@"lon"];
            CLLocation *location = [[CLLocation alloc] initWithLatitude:lat.doubleValue longitude:lon.doubleValue];
            if (self.delegate != nil && [self.delegate respondsToSelector:@selector(communicator:didReceiveLocation:fromPerson:)])
            {
                [self.delegate communicator:self didReceiveLocation:location fromPerson:messageInfo[@"person"]];
            }
        }
    }
    else if ([messageInfo[@"key"] isEqualToNumber:@2])
    {
        // so this isn't actually working, I need to monitor when someone enters or exits a channel as well...
        // they are sending a person
        // checking that we didn't send the message
        if (![self.person isEqualToString:messageInfo[@"person"]])
        {
            [self.people addObject:messageInfo[@"person"]];
            if (self.delegate != nil && [self.delegate respondsToSelector:@selector(communicator:numberOfPeopleInGroupChanged:)])
            {
                [self.delegate communicator:self numberOfPeopleInGroupChanged:self.people];
            }
        }
    }
    /*else
    {
        // they are sending a test
    }*/
}

@end
