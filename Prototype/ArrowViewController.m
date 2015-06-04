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
    double scale;
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
    scale = 1.0;
    self.lookingForPeopleLabel.text = [NSString stringWithFormat:@"Looking for %@",self.targetPerson];
    
    NSLog(@"%@ is looking for %@",COMMUNICATOR.person,self.targetPerson);
}

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
            NSLog(@"heading:%f, angle:%f, angleDiff:%f, scale:%f",heading.trueHeading,angle,newAngle,scale);
            
            CGAffineTransform scaleTransform = CGAffineTransformMakeScale(scale, scale);
            CGAffineTransform rotationTransfrom = CGAffineTransformMakeRotation(DTOR(newAngle));
            CGAffineTransform transform = CGAffineTransformConcat(rotationTransfrom, scaleTransform);
            
            self.arrowImage.transform = transform;
        }
        self.pinImage.transform = CGAffineTransformMakeRotation(DTOR(-heading.trueHeading));
    }
}

- (void)didUpdateLocations
{
    if (self.targetLocation && self.userLocation)
    {
        CLLocationDistance distance = [self.userLocation distanceFromLocation:self.targetLocation];
        // if they are within 10m of each other, hide everything
        if (distance <= 10)
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
            
            // setting the size of the arrow based on distance
            // the market is ~600m long
            // ok so get the distance between the two points
            // scale it based on the distance, go between 0.3 and 1
            float marketMax = 400.f;
            float marketMin = 30.f;
            
            // if we are effectively out of the market
            if (distance > marketMax)
                distance = marketMax;
            else if (distance < marketMin)
                distance = marketMin;
            else
            {
                // normalise the value
                scale = (distance - marketMin) / (marketMax - marketMin);
            }
            // stopping it from being TOO small
            if (scale < 0.3)
                scale = 0.3;
            
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
