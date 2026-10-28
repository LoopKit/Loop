//
//  CurrentSetupView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopAlgorithm

struct CurrentSetupView: View {
    @StateObject private var viewModel: CurrentSetupViewModel
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    init(viewModel: @autoclosure @escaping () -> CurrentSetupViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        List {
            if let selected = viewModel.selected {
                Section {
                    Text(summary(selected))
                    if let comparison = viewModel.comparison {
                        if let before = comparison.before {
                            TimeInRangeStripe(title: NSLocalizedString("Before", comment: "Title of the time in range bar for the period before the setup change"), timeInRange: before.glucose.timeInRange)
                        }
                        TimeInRangeStripe(title: NSLocalizedString("Since Change", comment: "Title of the time in range bar for the period since the setup change"), timeInRange: comparison.after.glucose.timeInRange)
                    } else if viewModel.isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                }
                if let comparison = viewModel.comparison {
                    resultsSection(comparison)
                }
                if viewModel.isCurrentSelected, let builder = viewModel.outcomesPackageBuilder {
                    Section(footer: Text(NSLocalizedString("Help improve Loop by sending these results, and the history behind them, to the Loop developers. Sharing after about 2 weeks without setup changes is ideal, but you can share at any time. Any changes are included in the history.", comment: "Footer of the share outcomes link on the current setup screen"))) {
                        NavigationLink(destination: ShareOutcomesView(viewModel: ShareOutcomesViewModel(change: selected, builder: builder))) {
                            Text(NSLocalizedString("Share Outcomes with Loop Developers", comment: "Link to the share outcomes screen"))
                        }
                    }
                }
            } else if !viewModel.isLoading {
                Section {
                    Text(NSLocalizedString("No settings have been recorded yet.", comment: "Shown on the current setup screen when there is no settings history"))
                        .foregroundColor(.secondary)
                }
            }
            if let history = viewModel.history, !history.changes.isEmpty {
                historySection(history)
            }
            Section(footer: Text(NSLocalizedString("Changes to therapy settings, insulin type or model, dosing strategy and algorithm experiments start a new setup. Running a preset doesn't.\n\nAbout 2 weeks with the same setup is a good amount of time to see a change in outcomes such as time in range and lows. Over just a few days, ordinary day-to-day variation can hide or exaggerate the effect.", comment: "Footer explaining what starts a new setup and how long to keep one"))) {
                EmptyView()
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(NSLocalizedString("Current Setup", comment: "Title of the current setup screen"))
        .task { await viewModel.load() }
    }

    private func resultsSection(_ comparison: SetupComparison) -> some View {
        let before = comparison.before
        let after = comparison.after
        return Section(header: SectionHeader(label: NSLocalizedString("Results", comment: "Header of the setup comparison results")),
                       footer: Text(before == nil
                                    ? NSLocalizedString("Median glucose by time of day since the change, with its 25–75% band.", comment: "Setup comparison chart explanation without a before period")
                                    : NSLocalizedString("Median glucose by time of day: dashed for the 3 weeks before the change, solid since the change, with its 25–75% band.", comment: "Setup comparison chart explanation"))) {
            comparisonRow(NSLocalizedString("Time in Range", comment: "Setup comparison row for time in range"),
                          before?.timeInRange.map(percent), after.timeInRange.map(percent))
            comparisonRow(String(format: NSLocalizedString("Time Below %@", comment: "Setup comparison row for time below the low threshold (1: glucose value, e.g. 70 mg/dL)"), lowThreshold),
                          before?.timeBelowRange.map(percent), after.timeBelowRange.map(percent))
            comparisonRow(NSLocalizedString("Average Glucose", comment: "Setup comparison row for average glucose"),
                          before?.glucose.averageGlucose.map(glucose), after.glucose.averageGlucose.map(glucose))
            comparisonRow(NSLocalizedString("Insulin per Day", comment: "Setup comparison row for average daily insulin"),
                          before?.insulinPerDay.map(units), after.insulinPerDay.map(units))
            if !after.glucose.agpProfile.isEmpty {
                MedianComparisonChartView(before: before?.glucose.agpProfile ?? [], after: after.glucose.agpProfile, unit: displayGlucosePreference.unit)
                    .frame(height: 200)
                    .padding(.vertical, 8)
            }
        }
    }

    private func historySection(_ history: SetupHistory) -> some View {
        Section(header: SectionHeader(label: NSLocalizedString("Setup History", comment: "Header of the list of past setup changes")),
                footer: Text(NSLocalizedString("Tap a change to see results from that change until now, compared with the 3 weeks before it.", comment: "Footer of the setup history list"))) {
            ForEach(history.changes.reversed(), id: \.date) { change in
                Button {
                    viewModel.select(change)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateRange(change, end: history.end(of: change)))
                                .foregroundColor(.primary)
                            Text(change.itemsDescription)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            if let timeInRange = viewModel.timeInRange[change.date] {
                                Text(String(format: NSLocalizedString("%@ in range", comment: "Time in range for a period (1: percent)"), percent(timeInRange)))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                        if change == viewModel.selected {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
    }

    private func dateRange(_ change: SetupChange, end: Date?) -> String {
        guard let end else {
            return String(format: NSLocalizedString("%@ – Now", comment: "Date range of the current setup (1: start date)"), change.date.formatted(date: .abbreviated, time: .shortened))
        }
        return String(format: NSLocalizedString("%1$@ · %2$@", comment: "Start date and length of a past setup (1: start date, 2: duration)"), change.date.formatted(date: .abbreviated, time: .shortened), duration(from: change.date, to: end))
    }

    private func duration(from start: Date, to end: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        return formatter.string(from: max(60, end.timeIntervalSince(start))) ?? ""
    }

    private func comparisonRow(_ title: String, _ before: String?, _ after: String?) -> some View {
        LabeledContent(title) {
            if let before {
                Text(String(format: NSLocalizedString("%1$@ → %2$@", comment: "A value before and since the setup change (1: before, 2: since)"), before, after ?? "–"))
            } else {
                Text(after ?? "–")
            }
        }
        .monospacedDigit()
    }

    private var lowThreshold: String {
        displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 70))
    }

    private func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(fraction < 0.1 ? 1 : 0)))
    }

    private func glucose(_ mgdl: Double) -> String {
        displayGlucosePreference.format(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl))
    }

    private func units(_ value: Double) -> String {
        String(format: NSLocalizedString("%@ U", comment: "Insulin amount in units (1: number)"), value.formatted(.number.precision(.fractionLength(1))))
    }

    private func summary(_ change: SetupChange) -> String {
        guard !change.isLowerBound else {
            return String(format: NSLocalizedString("No setup change has been recorded since %@, so there's no earlier setup to compare with.", comment: "Setup summary when the start of the setup isn't known (1: date)"),
                          change.date.formatted(date: .abbreviated, time: .omitted))
        }
        let changed = ListFormatter.localizedString(byJoining: change.items.map(\.title))
        let isLatest = viewModel.history?.end(of: change) == nil
        var sentences: [String]
        if change.isInitialSetup {
            sentences = [String(format: NSLocalizedString("It's been %@ since your initial setup.", comment: "Setup summary first sentence for the initial setup (1: duration, e.g. 5 days)"), change.durationDescription)]
        } else if isLatest {
            sentences = [String(format: NSLocalizedString("It's been %1$@ since your last setup change: %2$@.", comment: "Setup summary first sentence (1: duration, e.g. 5 days, 2: list of what changed)"), change.durationDescription, changed)]
        } else {
            sentences = [String(format: NSLocalizedString("It's been %1$@ since your setup change on %2$@: %3$@.", comment: "Setup summary first sentence for an earlier setup change (1: duration, e.g. 5 days, 2: date of the change, 3: list of what changed)"),
                                change.durationDescription, change.date.formatted(date: .abbreviated, time: .omitted), changed)]
        }
        if !isLatest {
            sentences.append(NSLocalizedString("These results run until now, so they include the later changes.", comment: "Setup summary note when an earlier setup change is selected"))
        }
        guard let comparison = viewModel.comparison else {
            if !viewModel.isLoading {
                sentences.append(NSLocalizedString("Results appear after a day with the new setup.", comment: "Setup summary before a day has passed since the change"))
            }
            return sentences.joined(separator: " ")
        }
        let after = comparison.after
        if let before = comparison.before, let tirBefore = before.timeInRange, let tirAfter = after.timeInRange,
           let lowBefore = before.timeBelowRange, let lowAfter = after.timeBelowRange {
            sentences.append(String(format: NSLocalizedString("Compared with the %1$@ before it, time in range %2$@, and time below %3$@ %4$@.", comment: "Setup comparison summary (1: length of the before period, 2: time in range change, 3: low threshold, 4: time below range change)"),
                                    periodDescription(before.days),
                                    changeDescription(tirBefore, tirAfter, threshold: 0.01),
                                    lowThreshold,
                                    changeDescription(lowBefore, lowAfter, threshold: 0.005)))
        } else {
            sentences.append(NSLocalizedString("There isn't enough CGM data from before the change to compare with.", comment: "Setup summary when the period before the change has too little data"))
        }
        if after.glucose.percentActive < SetupComparison.minimumCGMActive {
            sentences.append(String(format: NSLocalizedString("CGM data covers only %@ of this setup's time.", comment: "Setup summary note about missing CGM data (1: percent)"), percent(after.glucose.percentActive)))
        }
        if comparison.isSettling {
            sentences.append(NSLocalizedString("With less than 2 weeks so far, these numbers can still change a lot.", comment: "Setup summary note while the new setup has run less than two weeks"))
        }
        return sentences.joined(separator: " ")
    }

    private func changeDescription(_ before: Double, _ after: Double, threshold: Double) -> String {
        if abs(after - before) < threshold {
            return String(format: NSLocalizedString("stayed about the same at %@", comment: "A percentage that didn't change much (1: percent)"), percent(after))
        }
        let format = after > before
            ? NSLocalizedString("rose from %1$@ to %2$@", comment: "A percentage that went up (1: before, 2: after)")
            : NSLocalizedString("fell from %1$@ to %2$@", comment: "A percentage that went down (1: before, 2: after)")
        return String(format: format, percent(before), percent(after))
    }

    private func periodDescription(_ days: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = abs(days - 7 * (days / 7).rounded()) <= 0.5 ? [.weekOfMonth] : [.day]
        formatter.unitsStyle = .full
        return formatter.string(from: days.rounded() * .days(1)) ?? ""
    }
}

extension SetupChange {
    var durationDescription: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        let duration = formatter.string(from: max(60, Date().timeIntervalSince(date))) ?? ""
        if isLowerBound {
            return String(format: NSLocalizedString("at least %@", comment: "Time since the setup last changed, when the change date is not known exactly (1: duration, e.g. 3 days)"), duration)
        }
        return duration
    }

    var itemsDescription: String {
        isInitialSetup
            ? NSLocalizedString("Initial setup", comment: "Setup change where the therapy settings were first entered")
            : ListFormatter.localizedString(byJoining: items.map(\.title))
    }
}

extension SetupChange.Item {
    var title: String {
        switch self {
        case .therapySetting(let setting):
            return setting.title
        case .insulinType:
            return NSLocalizedString("Insulin Type", comment: "Setup change item for the insulin type")
        case .insulinModel:
            return NSLocalizedString("Insulin Model", comment: "Setup change item for the insulin model")
        case .dosingStrategy:
            return NSLocalizedString("Dosing Strategy", comment: "Setup change item for the dosing strategy")
        case .experiment(let experiment, let enabled):
            let format = enabled
                ? NSLocalizedString("%@ turned on", comment: "Setup change item for an algorithm experiment turned on (1: experiment name)")
                : NSLocalizedString("%@ turned off", comment: "Setup change item for an algorithm experiment turned off (1: experiment name)")
            return String(format: format, experiment.title)
        }
    }
}

extension ExperimentOption {
    var title: String {
        switch self {
        case .guardAndRunway:
            return NSLocalizedString("Guard + Runway", comment: "Title of guard and runway experiment")
        case .glucoseBasedApplicationFactor:
            return NSLocalizedString("Glucose Based Partial Application", comment: "Title of glucose based partial application experiment")
        case .integralRetrospectiveCorrection:
            return NSLocalizedString("Integral Retrospective Correction", comment: "Title of integral retrospective correction experiment")
        }
    }
}
