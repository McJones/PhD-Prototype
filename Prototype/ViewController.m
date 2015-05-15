//
//  ViewController.m
//  Prototype
//
//  Created by Timothy Rodney Nugent on 17/04/2015.
//  Copyright (c) 2015 Timothy Rodney Nugent. All rights reserved.
//

#import "ViewController.h"
#import "Communicator.h"
#import "PeopleTableViewController.h"

@interface ViewController () <UITextFieldDelegate,CommunicatorDelegate>
@property (weak, nonatomic) IBOutlet UITextField *textfield;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *throbber;
@property (weak, nonatomic) IBOutlet UILabel *connectingLabel;
@property (assign)          BOOL userConfigured;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    COMMUNICATOR.delegate = self;
    self.userConfigured = NO;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [COMMUNICATOR addPersonToGroup:textField.text];
    [self showThrobber];
    self.userConfigured = YES;
    return YES;
}

- (void)showThrobber
{
    self.throbber.hidden = NO;
    self.connectingLabel.hidden = NO;
    self.textfield.userInteractionEnabled = NO;
}
- (void)hideThrobber
{
    self.throbber.hidden = YES;
    self.connectingLabel.hidden = YES;
    self.textfield.userInteractionEnabled = YES;
}
- (void)communicator:(Communicator *)communicator didReceiveLocation:(CLLocation *)location fromPerson:(NSString *)person
{
    if (self.userConfigured)
        if (![COMMUNICATOR.person isEqualToString:person])
            [self performSegueWithIdentifier:@"showListSegue" sender:person];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSMutableArray *people = [@[sender] mutableCopy];
    
    PeopleTableViewController *destination = segue.destinationViewController;
    destination.people = people;
    
    [self hideThrobber];
}

@end
