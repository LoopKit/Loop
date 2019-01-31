//
//  CLKTextProvider+Compound.h
//  Loop
//
//  Created by Michael Pangburn on 10/27/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

#define CLKTextProvider_Compound_h

#import <ClockKit/ClockKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLKTextProvider (Compound)

+ (CLKTextProvider *)textProviderByJoiningTextProviders: (NSArray<CLKTextProvider *> *)textProviders separator:(NSString *) separator;

@end

NS_ASSUME_NONNULL_END
