//
//  RileyLinkDevice.m
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/28/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

#import "RileyLinkDevice.h"
#import "RileyLinkBLEManager.h"
#import "PumpOps.h"
#import "PumpOpsSynchronous.h"

NSString * const RileyLinkDeviceDidReceivePacketNotification = @"com.ps2.RileyLinkKit.RileyLinkDeviceDidReceivePacketNotification";

NSString * const RileyLinkDevicePacketKey = @"com.ps2.RileyLinkKit.RileyLinkDevicePacket";

@interface RileyLinkDevice () {
    PumpOps * _Nullable _ops;
}

@property (nonatomic, nonnull, strong) RileyLinkBLEDevice *device;

@end

@implementation RileyLinkDevice

@synthesize radioFrequency = _radioFrequency;
@synthesize lastTuned = _lastTuned;

- (instancetype)initWithBLEDevice:(RileyLinkBLEDevice *)device
{
    self = [super init];
    if (self) {
        _device = device;

        if (_device.peripheral.state == CBPeripheralStateConnected) {
            [_device enableIdleListeningOnChannel:0];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceNotificationReceived:) name:nil object:device];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:self.device];
}

- (NSString *)name
{
    return self.device.name;
}

- (NSNumber *)RSSI
{
    return self.device.RSSI;
}

- (CBPeripheral *)peripheral
{
    return self.device.peripheral;
}

- (void)setPumpID:(NSString *)pumpID
{
    if (_ops == nil || ![_ops.pump.pumpId isEqualToString:pumpID]) {
        PumpState *state = [[PumpState alloc] initWithPumpId:pumpID];
        _ops = [[PumpOps alloc] initWithPumpState:state andDevice:self.device];
    }
}

- (PumpState *)pumpState
{
    // TODO: Return a copy
    return _ops.pump;
}

- (NSString *)pumpID
{
    return [self.pumpState.pumpId copy];
}

#pragma mark -

- (void)deviceNotificationReceived:(NSNotification *)note
{
    if ([note.name isEqualToString:RILEYLINK_EVENT_PACKET_RECEIVED]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RileyLinkDeviceDidReceivePacketNotification object:self userInfo:@{RileyLinkDevicePacketKey: note.userInfo[@"packet"]}];
    } else if ([note.name isEqualToString:RILEYLINK_EVENT_DEVICE_CONNECTED]) {
        [self.device enableIdleListeningOnChannel:0];
    }
}

#pragma mark - Pump commands

- (void)tunePumpWithCompletionHandler:(void (^ _Nullable)(NSDictionary<NSString *, id> * _Nonnull))completionHandler {
    if (_ops != nil) {
        [_ops tunePump:^(NSDictionary * _Nonnull result) {
            if (result[@"bestFreq"] != nil && [result[@"bestFreq"] isKindOfClass:[NSNumber class]]) {
                _radioFrequency = result[@"bestFreq"];
                _lastTuned = [NSDate date];
            }

            completionHandler(result);
        }];
    } else {
        completionHandler(@{@"error": @"ConfigurationError: No pump configured"});
    }
}

- (void)runCommandWithShortMessage:(NSData *)firstMessage firstResponse:(uint8_t)firstResponse secondMessage:(NSData *)secondMessage secondResponse:(uint8_t)secondResponse completionHandler:(void (^)(NSData * _Nullable, NSString * _Nullable))completionHandler
{
    if (self.pumpState != nil) {
        [self.device runSession:^(RileyLinkCmdSession * _Nonnull session) {
            PumpOpsSynchronous *ops = [[PumpOpsSynchronous alloc] initWithPump:self.pumpState andSession:session];
            NSData *response;

            if ([ops sendData:firstMessage andListenForResponseType:firstResponse] != nil) {
                response = [ops sendData:secondMessage andListenForResponseType:secondResponse];
            }

            completionHandler(response, nil);
        }];
    } else {
        completionHandler(nil, @"ConfigurationError: No pump configured");
    }
}

@end
