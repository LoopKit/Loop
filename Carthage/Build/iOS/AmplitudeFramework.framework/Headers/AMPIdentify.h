//
//  AMPIdentify.h
//  Amplitude
//
//  Created by Daniel Jih on 10/5/15.
//  Copyright © 2015 Amplitude. All rights reserved.
//

@interface AMPIdentify : NSObject

@property (nonatomic, strong, readonly) NSMutableDictionary *userPropertyOperations;

+ (instancetype)identify;
- (AMPIdentify*)add:(NSString*) property value:(NSObject*) value;
- (AMPIdentify*)append:(NSString*) property value:(NSObject*) value;
- (AMPIdentify*)clearAll;
- (AMPIdentify*)prepend:(NSString*) property value:(NSObject*) value;
- (AMPIdentify*)set:(NSString*) property value:(NSObject*) value;
- (AMPIdentify*)setOnce:(NSString*) property value:(NSObject*) value;
- (AMPIdentify*)unset:(NSString*) property;

@end
