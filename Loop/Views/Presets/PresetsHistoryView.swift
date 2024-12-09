//
//  PresetsHistoryView.swift
//  Loop
//
//  Created by Cameron Ingham on 11/27/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI

struct PresetsHistoryView: View {
    
    @State var history: TemporaryScheduleOverrideHistory
    
    init () {
        self.history = TemporaryScheduleOverrideHistoryContainer.shared.fetch()
    }
    
    let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .short
        return formatter
    }()
    
    var body: some View {
        List {
            Section("Recent Events") {
                ForEach(history.recentEvents.sorted(by: { $0.override.actualEndDate > $1.override.actualEndDate }), id: \.self) { recentEvent in
                    
                    let scheduledDuration = recentEvent.override.duration.timeInterval
                    let actualDuration = recentEvent.override.actualDuration.timeInterval
                    
                    let value = scheduledDuration == actualDuration ? "\(formatter.string(from: scheduledDuration) ?? "")" : "\(formatter.string(from: actualDuration) ?? "") / \(formatter.string(from: scheduledDuration) ?? "")"
                
                    LabeledContent {
                        Text(value)
                    } label: {
                        Text(recentEvent.override.presetId)
                        
                        Text(recentEvent.override.startDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
    }
}

#Preview {
    PresetsHistoryView()
}
