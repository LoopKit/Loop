//
//  UpdateRegisterCmd.h
//  RileyLink
//
//  Created by Pete Schwamb on 1/25/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

#import "CmdBase.h"

@interface UpdateRegisterCmd : CmdBase

@property (nonatomic, assign) uint8_t addr;
@property (nonatomic, assign) uint8_t value;

@end
