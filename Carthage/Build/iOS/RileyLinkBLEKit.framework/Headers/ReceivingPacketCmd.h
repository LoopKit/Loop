//
//  ReceivingPacketCmd.h
//  RileyLink
//
//  Created by Pete Schwamb on 3/3/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

@import Foundation;
#import "CmdBase.h"
#import "RFPacket.h"

@interface ReceivingPacketCmd : CmdBase

@property (nonatomic, strong) RFPacket *receivedPacket;

@end
