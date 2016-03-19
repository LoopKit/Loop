//
//  RileyLinkDevice.h
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/28/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

@import Foundation;
@import CoreBluetooth;
#import "PumpState.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RileyLinkDeviceDidReceivePacketNotification;

extern NSString * const RileyLinkDevicePacketKey;

extern NSString * const RileyLinkDeviceDidChangeTimeNotification;

extern NSString * const RileyLinkDeviceTimeKey;

@interface RileyLinkDevice : NSObject

@property (copy, nonatomic, nullable, readonly) NSString *name;

@property (copy, nonatomic, nullable, readonly) NSNumber *RSSI;

@property (nonatomic, nonnull, readonly) CBPeripheral *peripheral;

@property (copy, nonatomic, nullable, readonly) PumpState *pumpState;

@property (nonatomic, nullable, readonly) NSDate *lastTuned;

@property (nonatomic, nullable, readonly) NSNumber *radioFrequency;

#pragma mark - Pump commands

- (void)tunePumpWithCompletionHandler:(void (^ _Nullable)(NSDictionary<NSString *, id> * _Nonnull))completionHandler;

- (void)runCommandWithShortMessage:(NSData *)firstMessage firstResponse:(uint8_t)firstResponse secondMessage:(nullable NSData *)secondMessage secondResponse:(uint8_t)secondResponse completionHandler:(void (^ _Nullable)(NSData * _Nullable response, NSString * _Nullable errorString))completionHandler;

- (void)runCommandWithShortMessage:(NSData *)firstMessage firstResponse:(uint8_t)firstResponse completionHandler:(void (^ _Nullable)(NSData * _Nullable response, NSString * _Nullable errorString))completionHandler;

- (void)sendTempBasalMessage:(NSData *)firstMessage secondMessage:(NSData *)secondMessage thirdMessage:(NSData *)thirdMessage withCompletionHandler:(void (^)(NSData * _Nullable response, NSString * _Nullable errorString))completionHandler;

- (void)sendChangeTimeMessage:(NSData *)firstMessage secondMessageGenerator:(NSData *(^)())secondMessageGenerator completionHandler:(void (^)(NSData * _Nullable response, NSString * _Nullable errorString))completionHandler;

@end

NS_ASSUME_NONNULL_END
