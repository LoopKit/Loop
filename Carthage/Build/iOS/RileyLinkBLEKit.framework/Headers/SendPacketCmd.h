//
//  SendPacketCmd.h
//  RileyLink
//
//  Created by Pete Schwamb on 12/27/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

@import Foundation;
#import "CmdBase.h"
#import "RFPacket.h"

@interface SendPacketCmd : CmdBase

@property (nonatomic, strong) RFPacket *packet;
@property (nonatomic, assign) uint8_t sendChannel; // In general, 0 = meter, cgm. 2 = pump
@property (nonatomic, assign) uint8_t repeatCount; // 0 = no repeat, i.e. only one packet.  1 repeat = 2 packets sent total.
@property (nonatomic, assign) uint8_t msBetweenPackets;

@end
