//
//  PresetPerformanceHistoryView.swift
//  Loop
//
//  Created by Cameron Ingham on 3/12/26.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

struct PresetPerformanceHistoryView: View {
    
    private enum DateRange: Hashable {
        case preset
        case presetPlus6Hours
        
        var localizedTitle: String {
            switch self {
            case .preset: return NSLocalizedString("During Preset", comment: "")
            case .presetPlus6Hours: return NSLocalizedString("Preset +6 Hours", comment: "")
            }
        }
        
        static func allCases(allowPlus6Hours: Bool) -> [DateRange] {
            if allowPlus6Hours {
                return [.preset, .presetPlus6Hours]
            } else {
                return [.preset]
            }
        }
    }
    
    private enum DataState {
        case loading
        case loaded(PresetsPerformanceHistoryViewModel.PerformanceData, plus6Hours: PresetsPerformanceHistoryViewModel.PerformanceData)
    }
    
    
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    
    @Environment(\.colorPalette) private var colorPalette
    @Environment(\.settingsManager) private var settingsManager
    
    @State private var state: DataState = .loading
    @State private var selectedDateRange: DateRange = .preset
    
    private let insulinFormatter = QuantityFormatter(for: .internationalUnit)
    private let carbFormatter = QuantityFormatter(for: .gram)

    let preset: SelectablePreset
    let override: TemporaryScheduleOverride
    let presetsPerformanceHistoryViewModel: PresetsPerformanceHistoryViewModel
    
    private var show6hrData: Bool {
        guard !override.isActive() else {
            return false
        }
        
        return override.actualEndDate.addingTimeInterval(.hours(6)) <= Date()
    }
    
    private var title: some View {
        HStack(spacing: 4) {
            if let icon = preset.icon, !icon.isEmpty {
                PresetSymbolView(icon, iconSize: UIFontMetrics.default.scaledValue(for: 28))
            }
            
            Text(preset.name)
                .fontWeight(.bold)
        }
        .font(.largeTitle)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                title
                
                switch state {
                case .loading:
                    ActivityIndicator(isAnimating: .constant(true), style: .medium)
                        .frame(maxWidth: .infinity)
                case .loaded(let data, let dataPlus6Hours):
                    VStack(spacing: 16) {
                        if data.minimalData {
                            minimalDataSection
                        }
                            
                        dateAndSettingsSection(performanceData: data)
                        
                        Picker("", selection: $selectedDateRange) {
                            ForEach(DateRange.allCases(allowPlus6Hours: true), id: \.self) { option in
                                Text(option.localizedTitle)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        detailsSection(
                            performanceData: selectedDateRange == .preset ? data : dataPlus6Hours,
                            showNoData: selectedDateRange == .presetPlus6Hours && !show6hrData
                        )
                    }
                }
            }
            .padding()
        }
        .animation(.default, value: selectedDateRange)
        .background(Color(UIColor.secondarySystemBackground))
        .task {
            await fetch()
        }
    }
    
    private var minimalDataSection: some View {
        GroupBox {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    
                Text("This summary is based on a preset with less than 30 minutes of CGM readings.")
                    .font(.subheadline)
            }
            .foregroundStyle(Color.accentColor)
        }
        .backgroundStyle(Color(UIColor.systemBackground))
    }
    
    private func dateAndSettingsSection(performanceData: PresetsPerformanceHistoryViewModel.PerformanceData) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
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
                    Text(performanceData.dateRange())
                        .fontWeight(.semibold)
                }
                
                Divider()
                
                PresetStatsView(
                    insulinMultiplier: performanceData.overallInsulin,
                    correctionRange: performanceData.correctionRange,
                    guardrail: settingsManager.correctionRangeGuardrailForPreset(preset),
                    therapySettingsImpactDisplayState: .hide,
                    isScheduled: false, // Not needed for hidden impact
                    isActive: false, // Not needed for hidden impact
                    effectiveCorrectionRange: { nil } // Not needed for hidden impact
                )
            }
        }
        .backgroundStyle(Color(UIColor.systemBackground))
    }
    
    private func detailsSection(performanceData: PresetsPerformanceHistoryViewModel.PerformanceData, showNoData: Bool) -> some View {
        GroupBox {
            if showNoData || performanceData.allGlucoseValues.isEmpty {
                Image("performance-history-empty")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .padding(20)
                    .background(Color(UIColor.systemBackground).clipShape(Circle()))
                
                VStack(spacing: 4) {
                    Text("No performance history available yet")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    
                    if showNoData {
                        Text("You can see this summary 6 hours after the preset ends.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    Text(performanceData.dateRange(overrideEndDate: override.isActive() ? Date() : nil))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Glucose Summary")
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let startingGlucose = performanceData.startingGlucose {
                                LabeledContent("Starting Glucose") {
                                    Group { Text(displayGlucosePreference.format(startingGlucose, includeUnit: false)).fontWeight(.semibold).foregroundStyle(.primary) + Text(" ") + Text(displayGlucosePreference.unit.localizedShortUnitString).foregroundStyle(.secondary) }.contentTransition(.numericText())
                                }
                            }
                                
                            if let averageGlucose = performanceData.averageGlucose {
                                LabeledContent("Average Glucose") {
                                    Group { Text(displayGlucosePreference.format(averageGlucose, includeUnit: false)).fontWeight(.semibold).foregroundStyle(.primary) + Text(" ") + Text(displayGlucosePreference.unit.localizedShortUnitString).foregroundStyle(.secondary) }.contentTransition(.numericText())
                                }
                            }
                        }
                    }
                    
                    HStack(spacing: 24) {
                        StackedBarView(
                            segments: [
                                .init(color: .glucoseVeryHigh, fraction: performanceData.timeInRange[.veryHigh] ?? 0),
                                .init(color: .glucoseHigh, fraction: performanceData.timeInRange[.high] ?? 0),
                                .init(color: .glucoseNormal, fraction: performanceData.timeInRange[.normal] ?? 0),
                                .init(color: .glucoseLow, fraction: performanceData.timeInRange[.low] ?? 0),
                                .init(color: .glucoseVeryLow, fraction: performanceData.timeInRange[.veryLow] ?? 0),
                            ]
                        )
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 24) {
                            GridRow {
                                Group { Text(String(format: "%.0f", (performanceData.timeInRange[.veryHigh] ?? 0) * 100)).font(.title2).bold().fontDesign(.monospaced) + Text(" %").font(.footnote) }
                                    .foregroundStyle(Color.glucoseVeryHigh)
                                    .contentTransition(.numericText())
                                
                                Text("Very High").font(.subheadline) + Text("  ") + Text(">\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 250), includeUnit: true))").font(.caption).foregroundStyle(.secondary)
                            }
                            
                            GridRow {
                                Group { Text(String(format: "%.0f", (performanceData.timeInRange[.high] ?? 0) * 100)).font(.title2).bold().fontDesign(.monospaced) + Text(" %").font(.footnote) }
                                    .foregroundStyle(Color.glucoseHigh)
                                    .contentTransition(.numericText())
                                
                                Text("High").font(.subheadline) + Text("  ") + Text("\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 181), includeUnit: false))-\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 250), includeUnit: true))").font(.caption).foregroundStyle(.secondary)
                            }
                            
                            GridRow {
                                Group { Text(String(format: "%.0f", (performanceData.timeInRange[.normal] ?? 0) * 100)).font(.title2).bold().fontDesign(.monospaced) + Text(" %").font(.footnote) }
                                    .foregroundStyle(Color.glucoseNormal)
                                    .contentTransition(.numericText())
                                
                                Text("Target").font(.subheadline).fontWeight(.semibold) + Text("  ") + Text("\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 70), includeUnit: false))-\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 180), includeUnit: true))").font(.caption).foregroundStyle(.secondary)
                            }
                            
                            GridRow {
                                Group { Text(String(format: "%.0f", (performanceData.timeInRange[.low] ?? 0) * 100)).font(.title2).bold().fontDesign(.monospaced) + Text(" %").font(.footnote) }
                                    .foregroundStyle(Color.glucoseLow)
                                    .contentTransition(.numericText())
                                
                                Text("Low").font(.subheadline) + Text("  ") + Text("\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 54), includeUnit: false))-\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 69), includeUnit: true))").font(.caption).foregroundStyle(.secondary)
                            }
                            
                            GridRow {
                                Group { Text(String(format: "%.0f", (performanceData.timeInRange[.veryLow] ?? 0) * 100)).font(.title2).bold().fontDesign(.monospaced) + Text(" %").font(.footnote) }
                                    .foregroundStyle(Color.glucoseVeryLow)
                                    .contentTransition(.numericText())
                                
                                Text("Very Low").font(.subheadline) + Text("  ") + Text("<\(displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 54), includeUnit: true))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(minHeight: 240)
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Overview")
                            .fontWeight(.semibold)
                        
                        Grid(horizontalSpacing: 16) {
                            GridRow(alignment: .top) {
                                if let carbString = carbFormatter.string(from: performanceData.totalCarbs, includeUnit: false) {
                                    VStack(spacing: 8) {
                                        Image("carbs")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 32, height: 32)
                                            .foregroundStyle(Color.carbs)
                                        
                                        VStack {
                                            Group {
                                                Text(carbString).fontWeight(.semibold) + Text(" \(LoopUnit.gram.localizedShortUnitString)").font(.footnote)
                                            }
                                            .foregroundStyle(Color.carbs)
                                            .contentTransition(.numericText())
                                            
                                            Text("Total\nCarbs")
                                                .multilineTextAlignment(.center)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                                
                                if let bolusString = insulinFormatter.string(from: performanceData.totalBolus, includeUnit: false) {
                                    VStack(spacing: 8) {
                                        Image("bolus")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 32, height: 32)
                                            .foregroundStyle(Color.insulin)
                                        
                                        VStack {
                                            Group {
                                                Text(bolusString).fontWeight(.semibold) + Text(" \(LoopUnit.internationalUnit.localizedShortUnitString)").font(.footnote)
                                            }
                                            .foregroundStyle(Color.insulin)
                                            .contentTransition(.numericText())
                                            
                                            Text("Total\nBolus")
                                                .multilineTextAlignment(.center)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                                
                                VStack(spacing: 8) {
                                    Image("automation-on-delivery-log")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                    
                                    VStack {
                                        Group {
                                            Text(String(format: "%.0f", performanceData.timeInAutomation * 100)).fontWeight(.semibold) + Text(" %").font(.footnote)
                                        }
                                        .contentTransition(.numericText())
                                        
                                        Text("Time in\nAutomation")
                                            .multilineTextAlignment(.center)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .backgroundStyle(Color(UIColor.systemBackground))
    }
    
    private func fetch() async {
        async let data = try? await presetsPerformanceHistoryViewModel.fetchData(from: override, add6Hours: false)
        async let dataPlus6Hours = try? await presetsPerformanceHistoryViewModel.fetchData(from: override, add6Hours: true)
        
        let combined = await (data, dataPlus6Hours)
        
        if let data = combined.0, let dataPlus6Hours = combined.1 {
            self.state = .loaded(data, plus6Hours: dataPlus6Hours)
        }
    }
}

struct StackedBarView: View {
    struct Segment {
        let color: Color
        let fraction: Double
    }
    
    let segments: [Segment]
    let cornerRadius: CGFloat = 8
    let width: CGFloat = 40
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    segment.color
                        .frame(height: heightFrom(index: index, totalHeight: geo.size.height))
                        .frame(maxWidth: .infinity)
                        .offset(y: offsetFor(index: index, totalHeight: geo.size.height))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .frame(width: width)
    }

    private func offsetFor(index: Int, totalHeight: CGFloat) -> CGFloat {
        segments[0..<index].reduce(0.0) { $0 + $1.fraction } * totalHeight
    }

    private func heightFrom(index: Int, totalHeight: CGFloat) -> CGFloat {
        segments[index...].reduce(0.0) { $0 + $1.fraction } * totalHeight
    }
}
