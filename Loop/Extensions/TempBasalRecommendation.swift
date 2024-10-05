//
//  TempBasalRecommendation.swift
//  Loop
//
//  Created by Pete Schwamb on 2/9/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopAlgorithm

extension TempBasalRecommendation {
    /// Equates the recommended rate with another rate
    ///
    /// - Parameter unitsPerHour: The rate to compare
    /// - Returns: Whether the rates are equal within Double precision
    private func matchesRate(_ unitsPerHour: Double) -> Bool {
        return abs(self.unitsPerHour - unitsPerHour) < .ulpOfOne
    }

    /// Adjusts a recommendation based on the current state of pump delivery. If the current temp basal matches
    /// the recommendation, and enough time is remaining, then recommend no action. If we are running a temp basal
    /// and the new rate matches the scheduled rate, then cancel the currently running temp basal. If the current scheduled
    /// rate matches the recommended rate, then recommend no action. Otherwise, set a new temp basal of the
    /// recommended rate.
    ///
    /// - Parameters:
    ///   - date: The date the recommendation would be delivered
    ///   - neutralBasalRate: The scheduled basal rate at `date`
    ///   - lastTempBasal: The previously set temp basal
    ///   - continuationInterval: The duration of time before an ongoing temp basal should be continued with a new command
    ///   - neutralBasalRateMatchesPump: A flag describing whether `neutralBasalRate` matches the scheduled basal rate of the pump.
    ///                                    If `false` and the recommendation matches `neutralBasalRate`, the temp will be recommended
    ///                                    at the scheduled basal rate rather than recommending no temp.
    /// - Returns: A temp basal recommendation
    func adjustForCurrentDelivery(
        at date: Date,
        neutralBasalRate: Double,
        currentTempBasal: DoseEntry?,
        continuationInterval: TimeInterval,
        neutralBasalRateMatchesPump: Bool
    ) -> TempBasalRecommendation? {
        // Adjust behavior for the currently active temp basal
        if let currentTempBasal, currentTempBasal.type == .tempBasal, currentTempBasal.endDate > date
        {
            /// If the last temp basal has the same rate, and has more than `continuationInterval` of time remaining, don't set a new temp
            if matchesRate(currentTempBasal.unitsPerHour),
               currentTempBasal.endDate.timeIntervalSince(date) > continuationInterval {
                return nil
            } else if matchesRate(neutralBasalRate), neutralBasalRateMatchesPump {
                // If our new temp matches the scheduled rate of the pump, cancel the current temp
                return .cancel
            }
        } else if matchesRate(neutralBasalRate), neutralBasalRateMatchesPump {
            // If we recommend the in-progress scheduled basal rate of the pump, do nothing
            return nil
        }

        return self
    }

    public static var cancel: TempBasalRecommendation {
        return self.init(unitsPerHour: 0, duration: 0)
    }
}

