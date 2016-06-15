//
//  AMPRevenue.h
//  Amplitude
//
//  Created by Daniel Jih on 04/18/16.
//  Copyright © 2016 Amplitude. All rights reserved.
//

@interface AMPRevenue : NSObject

// required fields
@property (nonatomic, strong, readonly) NSString *productId;
@property (nonatomic, readonly) NSInteger quantity;
@property (nonatomic, strong, readonly) NSNumber *price;

// optional fields
@property (nonatomic, strong, readonly) NSString *revenueType;
@property (nonatomic, strong, readonly) NSData *receipt;
@property (nonatomic, strong, readonly) NSDictionary *properties;

+ (instancetype)revenue;
- (BOOL) isValidRevenue;
- (AMPRevenue*)setProductIdentifier:(NSString*) productIdentifier;
- (AMPRevenue*)setQuantity:(NSInteger) quantity;
- (AMPRevenue*)setPrice:(NSNumber*) price;
- (AMPRevenue*)setRevenueType:(NSString*) revenueType;
- (AMPRevenue*)setReceipt:(NSData*) receipt;
- (AMPRevenue*)setEventProperties:(NSDictionary*) eventProperties;
- (NSDictionary*)toNSDictionary;

@end
