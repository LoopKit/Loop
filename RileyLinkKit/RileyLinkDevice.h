//
//  RileyLinkDevice.h
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/28/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

@import Foundation;
@import CoreBluetooth;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RileyLinkDeviceDidReceivePacketNotification;

extern NSString * const RileyLinkDevicePacketKey;

@interface RileyLinkDevice : NSObject

- (void)executeCommand:(nonnull id)command withCompletionHandler:(void (^ _Nonnull)(id _Nonnull command))completionHandler;

- (void)sendMessageData:(nonnull NSData *)messageData;

@property (copy, nonatomic, nullable, readonly) NSString *name;

@property (copy, nonatomic, nullable, readonly) NSNumber *RSSI;

@property (nonatomic, nonnull, readonly) CBPeripheral *peripheral;

@end

NS_ASSUME_NONNULL_END
