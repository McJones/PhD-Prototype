//
//  ArrowViewController.m
//  Prototype
//
//  Created by Timothy Rodney Nugent on 17/04/2015.
//  Copyright (c) 2015 Timothy Rodney Nugent. All rights reserved.
//

#import "ArrowViewController.h"
@import CoreLocation;
#import "Communicator.h"

#define IMPOSSIBLE 10000
#define DTOR(degrees) (M_PI * degrees / 180.0)
#define RTOD(radians) (radians * 180.0 / M_PI)

@interface ArrowViewController ()<CommunicatorDelegate,CLLocationManagerDelegate>
{
    double angle;
}

@property (strong, nonatomic) CLLocationManager *manager;
@property (strong, nonatomic) CLLocation *userLocation;
@property (strong, nonatomic) CLLocation *targetLocation;
@property (weak, nonatomic) IBOutlet UIImageView *arrowImage;
@property (weak, nonatomic) IBOutlet UIImageView *pinImage;
@property (weak, nonatomic) IBOutlet UIView *compassView;
@property (weak, nonatomic) IBOutlet UILabel *lookingForPeopleLabel;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *searchThrobber;

@end

@implementation ArrowViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    COMMUNICATOR.delegate = self;
    
    angle = IMPOSSIBLE;
    self.lookingForPeopleLabel.text = [NSString stringWithFormat:@"Looking for %@",self.targetPerson];
    
    NSLog(@"%@ is looking for %@",COMMUNICATOR.person,self.targetPerson);
    
    /*if ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusDenied || [CLLocationManager authorizationStatus] != kCLAuthorizationStatusRestricted)
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
    }*/
}

/*- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    CLLocation *location = locations.lastObject;
    if (self.userLocation)
    {
        if (location.horizontalAccuracy < 20 && location.horizontalAccuracy >= 0)
        {
            self.userLocation = location;
            [COMMUNICATOR sendLocation:self.userLocation];
            [self didUpdateLocations];
        }
    }
    else
    {
        self.userLocation = location;
        [COMMUNICATOR sendLocation:self.userLocation];
        [self didUpdateLocations];
    }
}*/
- (void)communicator:(Communicator *)communicator didReceiveLocation:(CLLocation *)location fromPerson:(NSString *)person
{
    // if the location came from our hardware or someone else
    if ([person isEqualToString:COMMUNICATOR.person])
    {
        if (self.userLocation)
        {
            if (location.horizontalAccuracy < 20 && location.horizontalAccuracy >= 0)
            {
                self.userLocation = location;
                [COMMUNICATOR sendLocation:self.userLocation];
            }
        }
        else
        {
            self.userLocation = location;
            [COMMUNICATOR sendLocation:self.userLocation];
        }
    }
    else
    {
        // if it came from the person we wanted
        if ([person isEqualToString:self.targetPerson])
            self.targetLocation = location;
    }
    [self didUpdateLocations];
}
- (void)communicator:(Communicator *)communicator didUpdateHeading:(CLHeading *)heading
{
    if (heading.headingAccuracy >= 0)
    {
        if (angle != IMPOSSIBLE)
        {
            double newAngle = angle - heading.trueHeading;
            NSLog(@"heading:%f,angle:%f,angleDiff:%f",heading.trueHeading,angle,newAngle);
            self.arrowImage.transform = CGAffineTransformMakeRotation(DTOR(newAngle));
        }
        self.pinImage.transform = CGAffineTransformMakeRotation(DTOR(-heading.trueHeading));
    }
}
/*- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
    if (newHeading.headingAccuracy >= 0)
    {
        if (angle != IMPOSSIBLE)
        {
            double newAngle = angle - newHeading.trueHeading;
            NSLog(@"heading:%f,angle:%f,angleDiff:%f",newHeading.trueHeading,angle,newAngle);
            self.arrowImage.transform = CGAffineTransformMakeRotation(DTOR(newAngle));

            // this way rotates the whole view back to north then moves the arrow to its position
            //self.arrowImage.transform = CGAffineTransformMakeRotation(DTOR(angle));
            //self.compassView.transform = CGAffineTransformMakeRotation(DTOR(-newHeading.trueHeading));
        }
        self.pinImage.transform = CGAffineTransformMakeRotation(DTOR(-newHeading.trueHeading));
    }
}*/

- (void)didUpdateLocations
{
    if (self.targetLocation && self.userLocation)
    {
        // if they are within 10m of each other, hide everything
        if ([self.userLocation distanceFromLocation:self.targetLocation] <= 10)
        {
            self.lookingForPeopleLabel.text = @"You are within 10m of each other";
            self.lookingForPeopleLabel.hidden = NO;
            self.searchThrobber.hidden = YES;
            self.compassView.hidden = YES;
        }
        else
        {
            double uLat = DTOR(self.userLocation.coordinate.latitude);
            double uLon = DTOR(self.userLocation.coordinate.longitude);
            double tLat = DTOR(self.targetLocation.coordinate.latitude);
            double tLon = DTOR(self.targetLocation.coordinate.longitude);
            
            double degrees = RTOD(atan2(sin(tLon-uLon)*cos(tLat), cos(uLat)*sin(tLat)-sin(uLat)*cos(tLat)*cos(tLon-uLon)));
            
            if (degrees >= 0)
                angle = degrees;
            else
                angle = 360 + degrees;
            
            // toggle off the looking for people, toggle on the arrow
            self.lookingForPeopleLabel.text = [NSString stringWithFormat:@"Looking for %@",self.targetPerson];
            self.searchThrobber.hidden = YES;
            self.lookingForPeopleLabel.hidden = YES;
            self.compassView.hidden = NO;
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
/*- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}*/
- (IBAction)tap:(id)sender {
    if (self.pinImage.hidden)
        self.pinImage.hidden = NO;
    else
        self.pinImage.hidden = YES;
}
- (IBAction)meetMeTapped:(id)sender {
    UIPasteboard *board = [UIPasteboard generalPasteboard];
    [board setString:[NSString stringWithFormat:@"lat:%f lon:%f",self.userLocation.coordinate.latitude,self.userLocation.coordinate.longitude]];
}

@end
