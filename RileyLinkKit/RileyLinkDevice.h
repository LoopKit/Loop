//
//  RileyLinkDevice.h
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/28/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

@import Foundation;
@import CoreData;

#import "RileyLinkBLEDevice.h"
#import "MessageSendOperationGroup.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RileyLinkDeviceDidReceivePacketNotification;

extern NSString * const RileyLinkDevicePacketKey;

@interface RileyLinkDevice : NSObject

- (nonnull instancetype)initWithBLEDevice:(nonnull RileyLinkBLEDevice *)device;

- (void)executeCommand:(nonnull id<MessageSendOperationGroup>)command withCompletionHandler:(void (^ _Nonnull)(id<MessageSendOperationGroup> _Nonnull command))completionHandler;

- (void)sendMessageData:(nonnull NSData *)messageData;

@property (copy, nonatomic, nullable, readonly) NSString *name;

@property (copy, nonatomic, nullable, readonly) NSNumber *RSSI;

@property (nonatomic, nonnull, readonly) CBPeripheral *peripheral;

@end

NS_ASSUME_NONNULL_END
