//
//  SendDataCmd.h
//  RileyLink
//
//  Created by Pete Schwamb on 8/9/15.
//  Copyright (c) 2015 Pete Schwamb. All rights reserved.
//

@import Foundation;
#import "ReceivingPacketCmd.h"
#import "RFPacket.h"

@interface SendAndListenCmd : ReceivingPacketCmd

@property (nonatomic, strong) RFPacket *packet;
@property (nonatomic, assign) uint8_t sendChannel; // In general, 0 = meter, cgm. 2 = pump
@property (nonatomic, assign) uint8_t repeatCount; // 0 = no repeat, i.e. only one packet.  1 repeat = 2 packets sent total.
@property (nonatomic, assign) uint8_t msBetweenPackets;
@property (nonatomic, assign) uint8_t listenChannel;
@property (nonatomic, assign) uint16_t timeoutMS;
@property (nonatomic, assign) uint8_t retryCount;

@end
