//
//  LoopMath.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/24/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public struct LoopMath {
    public static func simulationDateRangeForSamples(
        samples: [SampleValue],
        fromDate: NSDate? = nil,
        toDate: NSDate? = nil,
        duration: NSTimeInterval,
        delay: NSTimeInterval = 0,
        delta: NSTimeInterval) -> (NSDate, NSDate)?
    {
        guard samples.count > 0 else {
            return nil
        }

        let startDate: NSDate
        let endDate: NSDate

        if let fromDate = fromDate, toDate = toDate {
            startDate = fromDate
            endDate = toDate
        } else {
            var minDate = samples.first!.startDate
            var maxDate = minDate

            for sample in samples {
                if sample.startDate < minDate {
                    minDate = sample.startDate
                }

                if sample.startDate > maxDate {
                    maxDate = sample.startDate
                }
            }

            startDate = fromDate ?? minDate.dateFlooredToTimeInterval(delta)
            endDate = toDate ?? maxDate.dateByAddingTimeInterval(duration + delay).dateCeiledToTimeInterval(delta)
        }
        
        return (startDate, endDate)
    }
}