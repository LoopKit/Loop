//
//  RileyLinkDevice.m
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/28/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

#import "RileyLinkDevice.h"
#import "RileyLinkBLEManager.h"

NSString * const RileyLinkDeviceDidReceivePacketNotification = @"com.ps2.RileyLinkKit.RileyLinkDeviceDidReceivePacketNotification";

NSString * const RileyLinkDevicePacketKey = @"com.ps2.RileyLinkKit.RileyLinkDevicePacket";

@interface RileyLinkDevice ()

@property (nonatomic, nonnull, strong) RileyLinkBLEDevice *device;

@end

@implementation RileyLinkDevice

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

#pragma mark -

- (void)deviceNotificationReceived:(NSNotification *)note
{
    if ([note.name isEqualToString:RILEYLINK_EVENT_PACKET_RECEIVED]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:RileyLinkDeviceDidReceivePacketNotification object:self userInfo:@{RileyLinkDevicePacketKey: note.userInfo[@"packet"]}];
    } else if ([note.name isEqualToString:RILEYLINK_EVENT_DEVICE_CONNECTED]) {
        [self.device enableIdleListeningOnChannel:0];
    }
}

@end
