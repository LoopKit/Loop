//
//  PresetsHistoryView.swift
//  Loop
//
//  Created by Cameron Ingham on 11/27/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopCore
import LoopKitUI
import SwiftUI

struct PresetsHistoryView: View {
    @Environment(\.colorPalette) private var colorPalette
    @Environment(\.settingsManager) private var settingsManager
    @Environment(\.temporaryPresetsManager) private var temporaryPresetsManager
    
    let presetsPerformanceHistoryViewModel: PresetsPerformanceHistoryViewModel
    
    init(
        temporaryPresetsManager: TemporaryPresetsManager,
        glucoseStore: GlucoseStoreProtocol,
        carbStore: CarbStoreProtocol,
        doseStore: DoseStoreProtocol,
        automationHistory: @escaping () -> [AutomationHistoryEntry]
    ) {
        presetsPerformanceHistoryViewModel = PresetsPerformanceHistoryViewModel(
            temporaryPresetsManager: temporaryPresetsManager,
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            doseStore: doseStore,
            automationHistory: automationHistory
        )
    }

    let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    let now = Date()
    
    var overrides: Dictionary<Bool, [TemporaryScheduleOverride]> {
        Dictionary(
            grouping: temporaryPresetsManager.presetHistory.recentEvents
                .map(\.override)
                .filter({ $0.actualEndDate > now.addingTimeInterval(.days(-7)) })
                .sorted(by: { $0.startDate > $1.startDate })
        ) { override in
            override.isActive() || override.actualEndDate > now.addingTimeInterval(.days(-1))
        }
    }
    
    var body: some View {
        Group {
            if overrides.values.flatMap({ $0 }).isEmpty {
                ZStack {
                    Color(UIColor.secondarySystemBackground)
                        .ignoresSafeArea(edges: .all)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image("performance-history-empty")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .padding(20)
                            .background(Color(UIColor.systemBackground).clipShape(Circle()))
                        
                        VStack(spacing: 4) {
                            Text("No performance history available yet")
                                .multilineTextAlignment(.center)
                            
                            Text("To see how presets can support you, review the training.")
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                }
            } else {
                List {
                    ForEach(Array(overrides.keys).sorted { $0 && !$1 }, id: \.self) { isLast24Hrs in
                        Section(isLast24Hrs ? NSLocalizedString("LAST 24 HOURS", comment: "Preset Performance History, Last 24 hrs, Section title") : NSLocalizedString("LAST 7 DAYS", comment: "Preset Performance History, Last 7 days, Section title")) {
                            ForEach(overrides[isLast24Hrs] ?? [], id: \.self) { override in
                                if let preset = temporaryPresetsManager.selectablePresets.first(where: { $0.id == override.presetId }) {
                                    NavigationLink {
                                        PresetPerformanceHistoryView(
                                            preset: preset,
                                            override: override,
                                            presetsPerformanceHistoryViewModel: presetsPerformanceHistoryViewModel
                                        )
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 4) {
                                                if let icon = preset.icon, !icon.isEmpty {
                                                    PresetSymbolView(icon)
                                                }
                                                
                                                Text(preset.name)
                                                    .fontWeight(.semibold)
                                            }
                                            
                                            if override.isActive(), let expectedEndTime = override.expectedEndTime {
                                                HStack(spacing: 8) {
                                                    Text(Image(systemName: "timer"))
                                                    +
                                                    Text(" \(expectedEndTime.localizedTitle)")
                                                        .accessibilityLabel(Text(expectedEndTime.accessibilityLabel))
                                                }
                                                .font(.footnote)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 5)
                                                .background(Color(colorPalette.chartColorPalette.presetTint))
                                                .cornerRadius(8)
                                            } else {
                                                Text(PresetsPerformanceHistoryViewModel.dateRange(from: override.startDate, to: override.actualEndDate))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Performance History")
    }
}
