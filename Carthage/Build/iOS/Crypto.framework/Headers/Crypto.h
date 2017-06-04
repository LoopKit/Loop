//
//  Crypto.h
//  Crypto
//
//  Created by Nate Racklyeft on 9/13/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

#import <UIKit/UIKit.h>

//! Project version number for Crypto.
FOUNDATION_EXPORT double CryptoVersionNumber;

//! Project version string for Crypto.
FOUNDATION_EXPORT const unsigned char CryptoVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <Crypto/PublicHeader.h>


@interface NSString (Crypto)

@property (nonatomic, nonnull, readonly) NSString *sha1;

@end
