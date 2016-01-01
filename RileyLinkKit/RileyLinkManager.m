//
//  RileyLinkManager.m
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/28/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

#import "RileyLinkManager.h"
#import "RileyLinkDevice_Private.h"
#import "RileyLinkBLEDevice.h"
#import "RileyLinkBLEManager.h"

NSString * const RileyLinkManagerDidDiscoverDeviceNotification = @"com.ps2.RileyLinkKit.RileyLinkManagerDidDiscoverDevice";

NSString * const RileyLinkDeviceKey = @"com.ps2.RileyLinkKit.RileyLinkDevice";

@interface RileyLinkManager ()

@property (nonatomic, nonnull, strong) RileyLinkBLEManager *BLEManager;

@property (nonatomic, nonnull, strong) NSMutableArray<RileyLinkDevice *>* mutableDevices;

@property (nonatomic, nonnull, strong) NSSet<NSString *> *autoconnectIDs;

@property (copy, nonatomic, nonnull) NSString *pumpID;

@end

@implementation RileyLinkManager

- (instancetype)initWithPumpID:(NSString *)pumpID autoconnectIDs:(NSSet<NSString *> *)autoconnectIDs
{
    self = [super init];
    if (self) {
        _pumpID = pumpID;
        _autoconnectIDs = autoconnectIDs;
        _mutableDevices = [NSMutableArray array];

        _BLEManager = [[RileyLinkBLEManager alloc] init];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(discoveredBLEDevice:)
                                                     name:RILEYLINK_EVENT_LIST_UPDATED
                                                   object:_BLEManager];

        _BLEManager.autoConnectIds = _autoconnectIDs;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:RILEYLINK_EVENT_LIST_UPDATED
                                                  object:_BLEManager];
}

#pragma mark -

- (NSArray<RileyLinkDevice *> *)devices
{
    return self.mutableDevices;
}

- (BOOL)deviceScanningEnabled
{
    return self.BLEManager.isScanningEnabled;
}

- (void)setDeviceScanningEnabled:(BOOL)deviceScanningEnabled
{
    self.BLEManager.scanningEnabled = deviceScanningEnabled;
}

- (void)connectDevice:(RileyLinkDevice *)device
{
    [self.BLEManager connectPeripheral:device.peripheral];
}

- (void)disconnectDevice:(RileyLinkDevice *)device
{
    [self.BLEManager disconnectPeripheral:device.peripheral];
}

#pragma mark - RileyLinkBLEManager notifications

- (void)discoveredBLEDevice:(NSNotification *)note
{
    RileyLinkBLEDevice *BLEDevice = note.userInfo[@"device"];

    if (BLEDevice) {
        RileyLinkDevice *device = [[RileyLinkDevice alloc] initWithBLEDevice:BLEDevice];
        [self.mutableDevices addObject:device];

        [[NSNotificationCenter defaultCenter] postNotificationName:RileyLinkManagerDidDiscoverDeviceNotification
                                                            object:self
                                                          userInfo:@{RileyLinkDeviceKey: device}];
    }
}

@end
