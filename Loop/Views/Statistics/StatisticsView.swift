//
//  StatisticsView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopAlgorithm
import LoopUI

/// "How am I doing?" overview — an Ambulatory Glucose Profile report: summary
/// metrics, a time-in-range breakdown, and the 24-hour percentile AGP chart,
/// over a selectable look-back window.
struct StatisticsView: View {
    @StateObject private var viewModel: StatisticsViewModel
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    init(glucoseStore: GlucoseStoreProtocol, insulinDeliveryHistory: ((Int) async throws -> InsulinDeliveryHistory)? = nil, scheduledBasalTotal: Double? = nil) {
        _viewModel = StateObject(wrappedValue: StatisticsViewModel(glucoseStore: glucoseStore, insulinDeliveryHistory: insulinDeliveryHistory, scheduledBasalTotal: scheduledBasalTotal))
    }

    var body: some View {
        List {
            Section {
                Picker(NSLocalizedString("Range", comment: "Statistics date-range picker label"),
                       selection: $viewModel.selectedRange) {
                    ForEach(StatisticsViewModel.DateRange.allCases) { range in
                        Text("\(range.days)d").tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }

            if !viewModel.dataNotices.isEmpty {
                Section {
                    ForEach(viewModel.dataNotices, id: \.self) { line in
                        Label {
                            Text(line)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                }
            }

            if let stats = viewModel.statistics, stats.sampleCount > 0 {
                metricsSection(stats)
                timeInRangeSection(stats)
                agpSection(stats)
            } else if viewModel.isLoading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else {
                Section {
                    Text(NSLocalizedString("No glucose data for this period.", comment: "Statistics empty state"))
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.showsInsulin {
                insulinSection
            }
        }
        .navigationTitle(Text(NSLocalizedString("Statistics", comment: "Statistics screen title")))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Sections

    private func metricsSection(_ stats: GlucoseStatistics) -> some View {
        let averageGoal = displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 154))
        return Section(header: Text(NSLocalizedString("Glucose Metrics", comment: "Glucose metrics section header"))) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                metric(NSLocalizedString("GMI", comment: "Glucose Management Indicator metric title"),
                       value: stats.gmi.map { String(format: "%.1f%%", $0) },
                       goal: NSLocalizedString("Goal: <7%", comment: "GMI goal"))
                metric(NSLocalizedString("Average", comment: "Average glucose metric title"),
                       value: stats.averageGlucose.map {
                           displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: $0))
                       },
                       goal: String(format: NSLocalizedString("Goal: <%@", comment: "Average glucose goal"), averageGoal))
                metric(NSLocalizedString("Variability", comment: "Coefficient of variation metric title"),
                       value: stats.coefficientOfVariation.map { String(format: "%.0f%%", $0) },
                       goal: NSLocalizedString("Goal: ≤36%", comment: "Glucose variability goal"))
                metric(NSLocalizedString("CGM Active", comment: "Percent of time CGM data present metric title"),
                       value: String(format: "%.0f%%", stats.percentActive * 100),
                       goal: NSLocalizedString("Goal: >70%", comment: "CGM active goal"))
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func metric(_ title: String, value: String?, goal: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(value ?? "–")
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(goal)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func timeInRangeSection(_ stats: GlucoseStatistics) -> some View {
        Section(header: Text(NSLocalizedString("Time in Range", comment: "Time-in-range section header"))) {
            TimeInRangeBar(timeInRange: stats.timeInRange)
                .padding(.vertical, 8)
        }
    }

    private func units(_ value: Double) -> String {
        String(format: NSLocalizedString("%@ U", comment: "Insulin amount in units (1: number)"), value.formatted(.number.precision(.fractionLength(1))))
    }

    private func percent(_ part: Double, of total: Double) -> String {
        total > 0 ? (part / total).formatted(.percent.precision(.fractionLength(0))) : "–"
    }

    private var todayCaption: String {
        guard let typical = viewModel.typicalInsulinByNow, let today = viewModel.insulinToday else {
            return NSLocalizedString("Since midnight", comment: "Caption for insulin delivered today when there is no usual amount to compare")
        }
        return String(format: NSLocalizedString("Usually %1$@ by %2$@", comment: "Caption comparing today's insulin with the usual amount by this time (1: units, 2: time of day)"),
                      units(typical.median), today.end.formatted(date: .omitted, time: .shortened))
    }

    private var insulinSection: some View {
        let average = viewModel.averageInsulinDay
        return Section(header: Text(NSLocalizedString("Daily Insulin", comment: "Daily insulin section header")),
                       footer: Text(NSLocalizedString("Each bar is one calendar day; the dashed line is the average. Today isn't included until the day is over. Usual amounts are the median of the last 14 days at the same time of day.", comment: "Daily insulin section explanation"))) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                metric(NSLocalizedString("Average", comment: "Average daily insulin metric title"),
                       value: average.map { units($0.total) },
                       goal: String(format: NSLocalizedString("Per day, over %d days", comment: "Caption for average daily insulin (1: number of days)"), viewModel.insulinDays.count))
                metric(NSLocalizedString("Today", comment: "Insulin delivered today metric title"),
                       value: viewModel.insulinToday.map { units($0.totals.total) },
                       goal: todayCaption)
                metric(NSLocalizedString("Basal", comment: "Average daily basal metric title"),
                       value: average.map { units($0.basal) },
                       goal: average.map { average in
                           if let scheduled = viewModel.scheduledBasalTotal {
                               return String(format: NSLocalizedString("%1$@ · scheduled %2$@", comment: "Caption for average daily basal (1: percent of total, 2: scheduled basal units)"), percent(average.basal, of: average.total), units(scheduled))
                           }
                           return percent(average.basal, of: average.total)
                       } ?? "–")
                metric(NSLocalizedString("Bolus", comment: "Average daily bolus metric title"),
                       value: average.map { units($0.bolus) },
                       goal: average.map { average in
                           String(format: NSLocalizedString("%1$@ · %2$@ automatic", comment: "Caption for average daily bolus (1: percent of total, 2: automatic bolus units)"), percent(average.bolus, of: average.total), units(average.automaticBolus))
                       } ?? "–")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            if !viewModel.insulinDays.isEmpty {
                DailyInsulinChartView(days: viewModel.insulinDays, average: average?.total)
                    .frame(height: 220)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func agpSection(_ stats: GlucoseStatistics) -> some View {
        Section(header: Text(NSLocalizedString("Daily Glucose Pattern", comment: "Daily glucose pattern (AGP) section header")),
                footer: Text(NSLocalizedString("Median (line) with 25–75% and 5–95% bands, by time of day.", comment: "AGP chart explanation"))) {
            if stats.agpProfile.isEmpty {
                Text(NSLocalizedString("Not enough data to plot a profile.", comment: "AGP empty state"))
                    .foregroundColor(.secondary)
            } else {
                AGPChartView(profile: stats.agpProfile, unit: displayGlucosePreference.unit)
                    .frame(height: 240)
                    .padding(.vertical, 8)
            }
        }
    }
}

#if DEBUG
/// Generates a daily glucose pattern with day-to-day spread so the AGP bands and
/// metrics populate in the canvas. Deterministic (seeded) so previews are stable.
private final class PreviewGlucoseStore: GlucoseStoreProtocol {
    private let samples: [StoredGlucoseSample]

    init() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func unit01() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        let cal = Calendar.current
        let now = Date()
        let cadence: TimeInterval = 15 * 60
        var t = now.addingTimeInterval(-14 * 24 * 60 * 60)
        var out: [StoredGlucoseSample] = []
        while t < now {
            let hour = t.timeIntervalSince(cal.startOfDay(for: t)) / 3600
            let base = 140.0 + 40 * sin((hour - 4) / 24 * 2 * .pi)
            let value = max(45, base + (unit01() - 0.5) * 70)
            out.append(StoredGlucoseSample(startDate: t, quantity: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: value)))
            t = t.addingTimeInterval(cadence)
        }
        samples = out
    }

    var latestGlucose: GlucoseSampleValue? { samples.last }

    func getGlucoseSamples(start: Date?, end: Date?) async throws -> [StoredGlucoseSample] {
        samples.filter { (start == nil || $0.startDate >= start!) && (end == nil || $0.startDate < end!) }
    }

    func addGlucoseSamples(_ samples: [NewGlucoseSample]) async throws -> [StoredGlucoseSample] { [] }
}

#Preview {
    NavigationView {
        StatisticsView(glucoseStore: PreviewGlucoseStore())
            .environmentObject(DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter))
    }
}
#endif
