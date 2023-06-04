//
//  GlucoseBasedApplicationFactorSelectionView.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-04.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

public struct GlucoseBasedApplicationFactorSelectionView: View {
    @Binding var isGlucoseBasedApplicationFactorEnabled: Bool

    public init(isGlucoseBasedApplicationFactorEnabled: Binding<Bool>) {
        self._isGlucoseBasedApplicationFactorEnabled = isGlucoseBasedApplicationFactorEnabled
    }

    public var body: some View {
        List {
            automaticBolusSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("Glucose Based")
                        .font(.headline)
                    Text("Partial Application")
                        .font(.subheadline)
                }
            }
        }
    }

    private var automaticBolusSection: some View {
        VStack {
            DescriptiveText(label: NSLocalizedString("Active only when Automatic Bolus is selected under Dosing Strategy.\n\nWhen disabled, Automatic Bolus Dosing Strategy uses a constant percentage of 40% when Loop recommends a bolus.\n\nWhen enabled, this experimental feature varies the percentage of recommended bolus delivered each cycle with glucose level. Near correction range, use 20% (similar to Temp Basal). Gradually increase to a maximum of 80% at high glucose (200 mg/dL, 11.1 mmol/L).\n\nPlease be aware that during fast rising glucose, such as after an unannounced meal, this feature, combined with Loop's velocity and retrospective correction effects, may result in a larger dose than your ISF would call for.", comment: "Description of Glucose Based Partial Application toggle."), color: .black)
            Section() {
                Toggle(NSLocalizedString("Glucose Based Partial Application", comment: "Title for Glucose Based Partial Application toggle"), isOn: $isGlucoseBasedApplicationFactorEnabled)
                    .onChange(of: isGlucoseBasedApplicationFactorEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "applyExperimentalGlucoseBasedApplicationFactor")
                    }
            }
        }
    }
}

struct EnhancedAutoBolusSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        GlucoseBasedApplicationFactorSelectionView(isGlucoseBasedApplicationFactorEnabled: .constant(true))
    }
}
