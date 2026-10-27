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
    let setupChange: SetupChange?

    var body: some View {
        List {
            Section {
                if let setupChange {
                    LabeledContent(NSLocalizedString("Unchanged For", comment: "Title of the row showing how long the current setup has run"), value: setupChange.durationDescription)
                    LabeledContent(
                        setupChange.isLowerBound
                            ? NSLocalizedString("No Change Recorded Since", comment: "Title of the row showing the oldest date the setup is known to be unchanged since")
                            : NSLocalizedString("Last Change", comment: "Title of the row showing when the setup last changed"),
                        value: setupChange.date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text(NSLocalizedString("No settings have been recorded yet.", comment: "Shown on the current setup screen when there is no settings history"))
                        .foregroundColor(.secondary)
                }
            }
            if let setupChange, !setupChange.items.isEmpty {
                Section(header: SectionHeader(label: NSLocalizedString("What Changed", comment: "Header of the list of settings changed in the last setup change"))) {
                    ForEach(setupChange.items.indices, id: \.self) { index in
                        Text(setupChange.items[index].title)
                    }
                }
            }
            Section(footer: Text(NSLocalizedString("Changes to therapy settings, insulin type or model, dosing strategy and algorithm experiments start a new setup. Running a preset doesn't.\n\nAbout 2 weeks with the same setup is a good amount of time to see a change in outcomes such as time in range and lows. Over just a few days, ordinary day-to-day variation can hide or exaggerate the effect.", comment: "Footer explaining what starts a new setup and how long to keep one"))) {
                EmptyView()
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(NSLocalizedString("Current Setup", comment: "Title of the current setup screen"))
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
