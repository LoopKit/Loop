//
//  AESCrypt.h
//  xDripG5
//
//  Created by Nate Racklyeft on 6/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AESCrypt : NSObject

NS_ASSUME_NONNULL_BEGIN

+ (nullable NSData *)encryptData:(NSData *)data usingKey:(NSData *)key error:(NSError **)error;

NS_ASSUME_NONNULL_END

@end
