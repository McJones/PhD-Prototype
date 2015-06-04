//
//  PeopleTableViewController.m
//  Prototype
//
//  Created by Timothy Rodney Nugent on 17/04/2015.
//  Copyright (c) 2015 Timothy Rodney Nugent. All rights reserved.
//

#import "PeopleTableViewController.h"
#import "Communicator.h"
#import "ArrowViewController.h"

@interface PeopleTableViewController ()<CommunicatorDelegate>
{
    BOOL connected;
}

@end

@implementation PeopleTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = COMMUNICATOR.person;
    connected = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    COMMUNICATOR.delegate = self;
//    [COMMUNICATOR testLocation:YES];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)pauseButtonTapped:(id)sender {
    // also need to change the button image
    if (connected)
    {
        [COMMUNICATOR stopTracking];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay target:self action:@selector(pauseButtonTapped:)];
        connected = NO;
    }
    else
    {
        [COMMUNICATOR connectToNetwork];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPause target:self action:@selector(pauseButtonTapped:)];
        connected = YES;
    }
}

- (void)communicator:(Communicator *)communicator didReceiveLocation:(CLLocation *)location fromPerson:(NSString *)person
{
    NSLog(@"received location from %@",person);
    // if the person isn't us...
    if (![person isEqualToString:COMMUNICATOR.person])
    {
        if (self.people)
        {
            BOOL update = YES;
            for (NSString *peeps in self.people)
            {
                if ([person isEqualToString:peeps])
                {
                    update = NO;
                }
            }
            if (update)
            {
                [self.people addObject:person];
                [self.tableView reloadData];
            }
        }
        else
        {
            self.people = [@[person]mutableCopy];
            [self.tableView reloadData];
        }
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    return self.people.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PersonCell" forIndexPath:indexPath];
    
    // Configure the cell...
    cell.textLabel.text = self.people[indexPath.row];
    
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //[tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *targetPerson = self.people[indexPath.row];
    [self performSegueWithIdentifier:@"cellTappedSegue" sender:targetPerson];
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    if ([segue.identifier isEqualToString:@"cellTappedSegue"])
    {
        NSString *targetPerson = sender;
        ArrowViewController *destination = segue.destinationViewController;
        destination.targetPerson = targetPerson;
    }
}

@end
