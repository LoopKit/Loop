//
//  LoopCircleEntryView.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

struct LoopCircleEntryView: View {
    var entry: StatusWidgetTimelimeEntry

    var body: some View {
        let closedLoop = entry.closeLoop
        let lastLoopCompleted = entry.lastLoopCompleted ?? Date().addingTimeInterval(.minutes(16))
        let age = abs(min(0, lastLoopCompleted.timeIntervalSinceNow))
        let freshness = LoopCompletionFreshness(age: age)
        
        LoopCircleView(closedLoop: closedLoop, freshness: freshness)
            .disabled(entry.contextIsStale)
    }
}
