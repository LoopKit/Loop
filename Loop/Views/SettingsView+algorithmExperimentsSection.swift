//
//  SettingsView+algorithmExperimentsSection.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-03.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

extension SettingsView {
    internal var algorithmExperimentsSection: some View {
        NavigationLink(NSLocalizedString("Algorithm Experiments", comment: "The title of the Algorithm Experiments section in settings")) {
            ExperimentsSettingsView(automaticDosingStrategy: viewModel.automaticDosingStrategy)
        }
    }
}

public struct ExperimentRow: View {
    var name: String
    var enabled: Bool

    public var body: some View {
        HStack {
            Text(name)
                .foregroundColor(.primary)
            Spacer()
            Text(enabled ? "On" : "Off")
                .foregroundColor(enabled ? .red : .secondary)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .foregroundColor(.accentColor)
        .cornerRadius(10)
    }
}

public struct ExperimentsSettingsView: View {
    @AppStorage(UserDefaults.Key.GlucoseBasedApplicationFactorEnabled.rawValue) private var isGlucoseBasedApplicationFactorEnabled = false
    @AppStorage(UserDefaults.Key.IntegralRetrospectiveCorrectionEnabled.rawValue) private var isIntegralRetrospectiveCorrectionEnabled = false
    @AppStorage(UserDefaults.Key.GuardAndRunwayEnabled.rawValue) private var isGuardAndRunwayEnabled = false
    @AppStorage(UserDefaults.Key.SlowRetrospectiveCorrectionEnabled.rawValue) private var isSlowRetrospectiveCorrectionEnabled = false
    var automaticDosingStrategy: AutomaticDosingStrategy

    public var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 12) {
                Text(NSLocalizedString("Algorithm Experiments", comment: "Navigation title for algorithms experiments screen"))
                    .font(.headline)
                VStack {
                    Text("⚠️").font(.largeTitle)
                    Text("Caution")
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("Algorithm Experiments are optional modifications to the Loop Algorithm. These modifications are less tested than the standard Loop Algorithm, so please use carefully.", comment: "Algorithm Experiments description."))
                    Text(NSLocalizedString("In future versions of Loop these experiments may change, end up as standard parts of the Loop Algorithm, or be removed from Loop entirely. Please follow along in the Loop Zulip chat to stay informed of possible changes to these features.", comment: "Algorithm Experiments description second paragraph."))
                }
                .foregroundColor(.secondary)

                Divider()
                NavigationLink(destination: GuardAndRunwaySelectionView(isGuardAndRunwayEnabled: $isGuardAndRunwayEnabled)) {
                    ExperimentRow(
                        name: NSLocalizedString("Guard + Runway v2", comment: "Title of guard and runway experiment, second version"),
                        enabled: isGuardAndRunwayEnabled)
                }
                NavigationLink(destination: SlowRetrospectiveCorrectionSelectionView(isSlowRetrospectiveCorrectionEnabled: $isSlowRetrospectiveCorrectionEnabled)) {
                    ExperimentRow(
                        name: NSLocalizedString("Slow Retrospective Correction", comment: "Title of slow retrospective correction experiment"),
                        enabled: isSlowRetrospectiveCorrectionEnabled)
                }
                NavigationLink(destination: GlucoseBasedApplicationFactorSelectionView(isGlucoseBasedApplicationFactorEnabled: $isGlucoseBasedApplicationFactorEnabled, automaticDosingStrategy: automaticDosingStrategy)) {
                    ExperimentRow(
                        name: NSLocalizedString("Glucose Based Partial Application", comment: "Title of glucose based partial application experiment"),
                        enabled: isGlucoseBasedApplicationFactorEnabled && automaticDosingStrategy == .automaticBolus)
                }
                NavigationLink(destination: IntegralRetrospectiveCorrectionSelectionView(isIntegralRetrospectiveCorrectionEnabled: $isIntegralRetrospectiveCorrectionEnabled)) {
                    ExperimentRow(
                        name: NSLocalizedString("Integral Retrospective Correction", comment: "Title of integral retrospective correction experiment"),
                        enabled: isIntegralRetrospectiveCorrectionEnabled)
                }
                Text(NSLocalizedString("About 2 weeks with the same setup is a good amount of time to see a change in outcomes such as time in range and lows. Over just a few days, ordinary day-to-day variation can hide or exaggerate the effect.", comment: "Suggested length of time to try an algorithm experiment setup."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}


extension UserDefaults {
    fileprivate enum Key: String {
        case GlucoseBasedApplicationFactorEnabled = "com.loopkit.algorithmExperiments.glucoseBasedApplicationFactorEnabled"
        case IntegralRetrospectiveCorrectionEnabled = "com.loopkit.algorithmExperiments.integralRetrospectiveCorrectionEnabled"
        case GuardAndRunwayEnabled = "com.loopkit.algorithmExperiments.guardAndRunwayEnabled"
        case SlowRetrospectiveCorrectionEnabled = "com.loopkit.algorithmExperiments.slowRetrospectiveCorrectionEnabled"
    }

    var glucoseBasedApplicationFactorEnabled: Bool {
        get {
            bool(forKey: Key.GlucoseBasedApplicationFactorEnabled.rawValue) as Bool
        }
        set {
            set(newValue, forKey: Key.GlucoseBasedApplicationFactorEnabled.rawValue)
        }
    }

    var integralRetrospectiveCorrectionEnabled: Bool {
        get {
            bool(forKey: Key.IntegralRetrospectiveCorrectionEnabled.rawValue) as Bool
        }
        set {
            set(newValue, forKey: Key.IntegralRetrospectiveCorrectionEnabled.rawValue)
        }
    }

    var guardAndRunwayEnabled: Bool {
        get {
            bool(forKey: Key.GuardAndRunwayEnabled.rawValue) as Bool
        }
        set {
            set(newValue, forKey: Key.GuardAndRunwayEnabled.rawValue)
        }
    }

    var slowRetrospectiveCorrectionEnabled: Bool {
        get {
            bool(forKey: Key.SlowRetrospectiveCorrectionEnabled.rawValue) as Bool
        }
        set {
            set(newValue, forKey: Key.SlowRetrospectiveCorrectionEnabled.rawValue)
        }
    }

}
