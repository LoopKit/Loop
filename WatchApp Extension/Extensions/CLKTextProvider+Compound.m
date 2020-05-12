//
//  CLKTextProvider+Compound.m
//  WatchApp Extension
//
//  Created by Michael Pangburn on 10/27/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

#import "CLKTextProvider+Compound.h"

NS_ASSUME_NONNULL_BEGIN

// CLKTextProvider.textProviderWithFormat (compound text provider creation) is unavailable in Swift.
// c.f. https://crunchybagel.com/using-multicolour-clktextprovider-in-swift-in-watchos-5/
@implementation CLKTextProvider (Compound)

+ (CLKTextProvider *)textProviderByJoiningTextProviders: (NSArray<CLKTextProvider *> *)textProviders separator:(NSString *) separator {

    NSString *formatString = @"%@%@";

    if (separator.length > 0) {
        formatString = [NSString stringWithFormat:@"%@%@%@", @"%@", separator, @"%@"];
    }

    CLKTextProvider *firstItem = textProviders.firstObject;

    for (NSUInteger index = 1; index < textProviders.count; index++) {
        CLKTextProvider *secondItem = [textProviders objectAtIndex: index];
        firstItem = [CLKTextProvider textProviderWithFormat:formatString, firstItem, secondItem];
    }

    return firstItem;
}

@end

NS_ASSUME_NONNULL_END
