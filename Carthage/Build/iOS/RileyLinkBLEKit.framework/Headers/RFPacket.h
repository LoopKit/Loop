//
//  RFPacket.h
//  RileyLink
//
//  Created by Pete Schwamb on 2/28/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

@import Foundation;

@interface RFPacket : NSObject

- (nonnull instancetype)initWithData:(nonnull NSData*)data NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithRFSPYResponse:(nonnull NSData*)data NS_DESIGNATED_INITIALIZER;

- (nonnull NSData*)encodedData;

@property (nonatomic, nullable, strong) NSData *data;
@property (nonatomic, nullable, strong) NSDate *capturedAt;
@property (nonatomic, assign) int rssi;
@property (nonatomic, assign) int packetNumber;


@end
