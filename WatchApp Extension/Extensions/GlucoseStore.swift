//
//  GlucoseStore.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/26/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import WatchConnectivity

extension GlucoseStore {
    func maybeRequestGlucoseBackfill() {
        getCachedGlucoseSamples(start: .EarliestGlucoseCutoff) { samples in
            let latestDate = samples.last?.startDate ?? .EarliestGlucoseCutoff
            if latestDate < .StaleGlucoseCutoff {
                let userInfo = GlucoseBackfillRequestUserInfo(startDate: latestDate)
                WCSession.default.sendGlucoseBackfillRequestMessage(userInfo) { (context) in
                    self.addGlucose(context.samples) { _ in }
                }
            }
        }
    }
}
