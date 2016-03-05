//
//  RileyLinkDevice_Private.h
//  Naterade
//
//  Created by Nathan Racklyeft on 12/28/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

#import "RileyLinkBLEDevice.h"

@interface RileyLinkDevice ()

- (nonnull instancetype)initWithBLEDevice:(nonnull RileyLinkBLEDevice *)device;

@property (copy, nonatomic, nullable) NSString *pumpID;

@end
