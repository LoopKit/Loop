//
//  RileyLinkManager.h
//  RileyLink
//
//  Created by Nathan Racklyeft on 8/28/15.
//  Copyright © 2015 Pete Schwamb. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RileyLinkDevice.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const RileyLinkManagerDidDiscoverDeviceNotification;

extern NSString * const RileyLinkDeviceKey;

NS_ASSUME_NONNULL_END

@interface RileyLinkManager : NSObject

- (nonnull instancetype)initWithPumpID:(nonnull NSString *)pumpID autoconnectIDs:(nonnull NSSet<NSString *> *)autoconnectIDs;

@property (copy, nonatomic, nullable, readonly) NSString *pumpID;

@property (nonatomic, nonnull, readonly, strong) NSArray<RileyLinkDevice *>* devices;

@property (nonatomic, readwrite) BOOL deviceScanningEnabled;

- (void)connectDevice:(nonnull RileyLinkDevice *)device;

- (void)disconnectDevice:(nonnull RileyLinkDevice *)device;

@end
