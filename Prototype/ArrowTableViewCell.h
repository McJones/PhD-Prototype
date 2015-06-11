//
//  ArrowTableViewCell.h
//  Prototype
//
//  Created by Timothy Rodney Nugent on 5/06/2015.
//  Copyright (c) 2015 Timothy Rodney Nugent. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ArrowTableViewCell : UITableViewCell

@property (weak, nonatomic, readwrite) IBOutlet UIImageView *arrowImage;
@property (weak, nonatomic, readwrite) IBOutlet UILabel *deviceLabel;

@end
