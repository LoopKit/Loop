//
//  OverrideSelectionHistory.swift
//  LoopUI
//
//  Created by Anna Quinlan on 8/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

public class OverrideHistoryViewModel: ObservableObject {
    var overrides: [TemporaryScheduleOverride]

    public init(overrides: [TemporaryScheduleOverride]) {
        self.overrides = overrides
    }
}

public struct OverrideSelectionHistory: View {
    @ObservedObject var model: OverrideHistoryViewModel
    
    public init(model: OverrideHistoryViewModel) {
        self.model = model
    }
    
    public var body: some View {
        List {
            ForEach(model.overrides, id: \.self) { override in
                self.createCell(for: override)
            }
        }
        .listStyle(GroupedListStyle())
        .environment(\.horizontalSizeClass, .regular)
        .navigationBarTitle(Text(LocalizedString("Override History", comment: "Title for override history view")), displayMode: .inline)
    }
    
    private lazy var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    private func createCell(for override: TemporaryScheduleOverride) -> OverrideViewCell {
        let startTime = DateFormatter.localizedString(from: override.startDate, dateStyle: .none, timeStyle: .short)
        // ANNA TODO
//        if let targetRange = override.settings.targetRange {
//            cell.targetRangeLabel.text = makeTargetRangeText(from: targetRange)
//        } else {
//            cell.targetRangeLabel.isHidden = true
//        }
        
//        var duration: String
//        switch override.duration {
//        case .finite(let interval):
//            duration = durationFormatter.string(from: interval)!
//        case .indefinite:
//            duration = "∞"
//        }
        let duration = "10h"
        
        switch override.context {
        case .legacyWorkout:
            return OverrideViewCell(
                symbol: Text("🏃‍♂️"),
                startTime: Text(startTime),
                name: Text("Workout"),
                targetRange: Text("TODO"),
                duration: Text(duration)
            )
        case .preMeal:
            return OverrideViewCell(
                symbol: Text("🍽"),
                startTime: Text(startTime),
                name: Text("Pre-Meal"),
                targetRange: Text("TODO"),
                duration: Text(duration)
            )
        case .preset(let preset):
            return OverrideViewCell(
                symbol: Text(preset.symbol),
                startTime: Text(startTime),
                name: Text(preset.name),
                targetRange: Text("TODO"),
                duration: Text(duration)
            )
        case .custom:
            return OverrideViewCell(
                symbol: Text("..."),
                startTime: Text(startTime),
                name: Text("Custom"),
                targetRange: Text("TODO"),
                duration: Text(duration)
            )
        }

//        if let insulinNeedsScaleFactor = settings.insulinNeedsScaleFactor {
//            cell.insulinNeedsBar.progress = insulinNeedsScaleFactor
//        } else {
//            cell.insulinNeedsBar.isHidden = true
//        }

        
    }
}
