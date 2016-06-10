//
//  BaseCmd.h
//  RileyLink
//
//  Created by Pete Schwamb on 12/26/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

@import Foundation;

#define RILEYLINK_CMD_GET_STATE       1
#define RILEYLINK_CMD_GET_VERSION     2
#define RILEYLINK_CMD_GET_PACKET      3
#define RILEYLINK_CMD_SEND_PACKET     4
#define RILEYLINK_CMD_SEND_AND_LISTEN 5
#define RILEYLINK_CMD_UPDATE_REGISTER 6
#define RILEYLINK_CMD_RESET           7

@interface CmdBase : NSObject

@property (NS_NONATOMIC_IOSONLY, readonly, copy) NSData *data;

@property (nonatomic, strong) NSData *response;

@end
