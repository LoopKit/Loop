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
    @State private var isGlucoseBasedApplicationFactorEnabled = UserDefaults.standard.glucoseBasedApplicationFactorEnabled
    @State private var isIntegralRetrospectiveCorrectionEnabled = UserDefaults.standard.integralRetrospectiveCorrectionEnabled
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
                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}


extension UserDefaults {
    private enum Key: String {
        case GlucoseBasedApplicationFactorEnabled = "com.loopkit.algorithmExperiments.glucoseBasedApplicationFactorEnabled"
        case IntegralRetrospectiveCorrectionEnabled = "com.loopkit.algorithmExperiments.integralRetrospectiveCorrectionEnabled"
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

}
