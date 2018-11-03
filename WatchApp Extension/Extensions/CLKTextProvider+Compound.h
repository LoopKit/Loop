//
//  CLKTextProvider+Compound.h
//  Loop
//
//  Created by Michael Pangburn on 10/27/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

#ifndef CLKTextProvider_Compound_h
#define CLKTextProvider_Compound_h

#import <ClockKit/ClockKit.h>

@interface CLKTextProvider (Compound)

+ (CLKTextProvider *)textProviderByJoiningTextProviders: (nonnull NSArray<CLKTextProvider *> *)textProviders separator:(nullable NSString *) separator;

@end

#endif /* CLKTextProvider_Compound_h */
