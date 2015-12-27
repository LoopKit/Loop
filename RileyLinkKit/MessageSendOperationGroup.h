//
//  PumpCommand.h
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

@import Foundation;
#import "MessageSendOperation.h"
#import "MinimedPacket.h"

@protocol MessageSendOperationGroup <NSObject>

/**
 Returns the send operations, in order of execution.

 @return An array of operations
 */
- (nonnull NSArray <MessageSendOperation *>*)messageOperations;

/**
 Returns the type of packets in the operation group, used for proper channel configuration.

 @return A packet type enumeration
 */
- (PacketType)packetType;

@end
