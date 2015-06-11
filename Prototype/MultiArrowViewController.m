//
//  MultiArrowViewController.m
//  Prototype
//
//  Created by Timothy Rodney Nugent on 5/06/2015.
//  Copyright (c) 2015 Timothy Rodney Nugent. All rights reserved.
//

#import "MultiArrowViewController.h"
#import "Communicator.h"
#import "ArrowTableViewCell.h"

#define IMPOSSIBLE 10000

@interface MultiArrowViewController ()<UITableViewDataSource,UITableViewDelegate,CommunicatorDelegate>

@property (weak, nonatomic) IBOutlet UIImageView *arrowImageView;
@property (weak, nonatomic) IBOutlet UILabel *compassLabel;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *throbber;
@property (weak, nonatomic) IBOutlet UIView *compassContainer;
@property (weak, nonatomic) IBOutlet UITableView *peopleTableView;

@property (strong, nonatomic) NSMutableDictionary *people;
@property (strong, nonatomic) NSString *targetPerson;
@property (strong, nonatomic) CLLocation *userLocation;
@property (strong, nonatomic) CLHeading *facing;

@end

@implementation MultiArrowViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
//    [COMMUNICATOR testLocation:YES];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    COMMUNICATOR.delegate = self;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - tableview
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    return self.people.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ArrowTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ArrowCell" forIndexPath:indexPath];
    NSString *person = self.people.allKeys[indexPath.row];
    CLLocation *targetLocation = self.people[self.people.allKeys[indexPath.row]];

    if (self.userLocation)
    {
        // Configuring the arrow
        if (self.facing)
        {
            CLLocationDirection angle = [self heading:self.userLocation targetLocation:targetLocation];
            CLLocationDirection newHeading = angle - self.facing.trueHeading;
            CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(DTOR(newHeading));
            cell.arrowImage.transform = rotationTransform;
        }
    }
    cell.deviceLabel.text = person;
    
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *selectedPerson = self.people.allKeys[indexPath.row];
    // if they are not the person we are already looking for
    if (![self.targetPerson isEqualToString:selectedPerson])
    {
        self.targetPerson = self.people.allKeys[indexPath.row];
        self.compassLabel.text = [NSString stringWithFormat:@"Looking for %@",self.targetPerson];
    }
    
    self.arrowImageView.hidden = NO;
    self.throbber.hidden = YES;
}

#pragma mark - Communicator
- (void)communicator:(Communicator *)communicator didReceiveLocation:(CLLocation *)location fromPerson:(NSString *)person
{
    NSLog(@"received location from %@",person);
    // if the person isn't us...
    if (![person isEqualToString:COMMUNICATOR.person])
    {
        if (!self.people)
            self.people = [NSMutableDictionary new];
        
        // basically just set the new location for the person
        self.people[person] = location;
        [self.peopleTableView reloadData];
    }
    else
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
}
- (void)communicator:(Communicator *)communicator didUpdateHeading:(CLHeading *)heading
{
    if (heading.headingAccuracy >= 0)
    {
        for (NSString *personKey in self.people)
        {
            // if we are updating the main arrow
            if ([personKey isEqualToString:self.targetPerson])
            {
                CLLocation *target = self.people[personKey];
                double distance = [self.userLocation distanceFromLocation:target];
                
                if (distance > 10)
                {
                    CLLocationDirection angle = [self heading:self.userLocation targetLocation:target];
                    if (angle != IMPOSSIBLE)
                    {
                        CLLocationDirection newHeading = angle - heading.trueHeading;
                        CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(DTOR(newHeading));
                        
                        double scale = [self scale:self.userLocation targetLocation:target];
                        CGAffineTransform scaleTransform = CGAffineTransformMakeScale(scale, scale);
                        CGAffineTransform transform = CGAffineTransformConcat(rotationTransform, scaleTransform);
                        
                        self.arrowImageView.transform = transform;
                    }
                    
                    self.compassLabel.text = [NSString stringWithFormat:@"Looking for %@",self.targetPerson];
                }
                else
                {
                    self.compassLabel.text = @"You are within 10m";
                }
            }
            else
            {
                // if is someone else, do we even bother/care..?
                self.facing = heading;
                [self.peopleTableView reloadData];
            }
        }
    }
}

#pragma mark - location stuff
- (CLLocationDirection)heading:(CLLocation *)user targetLocation:(CLLocation *)target
{
    CLLocationDistance distance = [user distanceFromLocation:target];
    CLLocationDirection theAngle = IMPOSSIBLE;
    
    // if they are outside of 10m of each other
    if (distance > 10)
    {
        double uLat = DTOR(user.coordinate.latitude);
        double uLon = DTOR(user.coordinate.longitude);
        double tLat = DTOR(target.coordinate.latitude);
        double tLon = DTOR(target.coordinate.longitude);
        
        double degrees = RTOD(atan2(sin(tLon-uLon)*cos(tLat), cos(uLat)*sin(tLat)-sin(uLat)*cos(tLat)*cos(tLon-uLon)));
        
        if (degrees >= 0)
            theAngle = degrees;
        else
            theAngle = 360 + degrees;
    }
    return theAngle;
}
- (double)scale:(CLLocation *)user targetLocation:(CLLocation *)target
{
    CLLocationDistance distance = [user distanceFromLocation:target];
    double theScale = 1.0;
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
    
    // normalise the value
    theScale = (distance - marketMin) / (marketMax - marketMin);
    
    // stopping it from being TOO small
    if (theScale < 0.3)
        theScale = 0.3;
    
    return theScale;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
