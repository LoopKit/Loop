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
    
    let viewModel: PresetsViewModel
    @State var history: TemporaryScheduleOverrideHistory
    
    init (viewModel: PresetsViewModel) {
        self.viewModel = viewModel
        self.history = TemporaryScheduleOverrideHistoryContainer.shared.fetch()
    }
    
    let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    var overridesByDate: Dictionary<Date, [TemporaryScheduleOverride]> {
        Dictionary(
            grouping: history.recentEvents
                .map(\.override)
                .filter({ !$0.isActive() })
                .sorted(by: { $0.actualEndDate > $1.actualEndDate })
        ) { override in
            Calendar.current.startOfDay(for: override.startDate)
        }
    }
    
    var body: some View {
        List {
            ForEach(Array(overridesByDate.keys.sorted(by: >)), id: \.self) { date in
                Section(date.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(overridesByDate[date] ?? [], id: \.self) { override in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("Duration")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                
                                durationText(for: override)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(override.startDate.formatted(date: .omitted, time: .shortened))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                
                                if let preset = viewModel.allPresets.first(where: { $0.id == override.presetId }) {
                                    HStack(spacing: 4) {
                                        switch preset.icon {
                                        case .emoji(let emoji):
                                            Text(emoji)
                                        case .image(let name, let iconColor):
                                            Image(name)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .foregroundColor(iconColor)
                                                .frame(width: UIFontMetrics.default.scaledValue(for: 22), height: UIFontMetrics.default.scaledValue(for: 22))
                                        }
                                        
                                        Text(preset.name)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent Events")
    }
    
    @ViewBuilder
    func durationText(for override: TemporaryScheduleOverride) -> some View {
        switch override.duration {
        case let .finite(scheduledDuration):
            let actualDuration = override.actualDuration.timeInterval
            if let scheduledDurationString = formatter.string(from: scheduledDuration), let actualDurationString = formatter.string(from: actualDuration) {
                if scheduledDuration <= actualDuration {
                    Text(actualDurationString)
                        .foregroundStyle(.primary)
                } else {
                    Text(actualDurationString)
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                    + Text(" / ")
                    + Text(scheduledDurationString)
                }
            }
        case .indefinite:
            if let durationString = formatter.string(from: override.actualDuration.timeInterval) {
                Text(durationString)
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
            }
        }
    }
}
