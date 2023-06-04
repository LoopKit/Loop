//
//  EnhancedAutoBolusSelectionView.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-04.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

public struct EnhancedAutoBolusSelectionView: View {
    @Binding var isEnhancedAutoBolusEnabled: Bool

    public init(isEnhancedAutoBolusEnabled: Binding<Bool>) {
        self._isEnhancedAutoBolusEnabled = isEnhancedAutoBolusEnabled
    }

    public var body: some View {
        List {
            automaticBolusSection
        }
        .navigationTitle(NSLocalizedString("Enhanced AutoBolus", comment: "Title of Enhanced AutoBolus"))
    }

    private var automaticBolusSection: some View {
        Section(footer: DescriptiveText(label: NSLocalizedString("Active only when Automatic Bolus is selected under Dosing Strategy.\n\nWhen disabled, Automatic Bolus Dosing Strategy uses a constant percentage of 40% when Loop recommends a bolus.\n\nWhen enabled, this experimental feature varies the percentage of recommended bolus delivered each cycle with glucose level. Near correction range, use 20% (similar to Temp Basal). Gradually increase to a maximum of 80% at high glucose (200 mg/dL, 11.1 mmol/L).\n\nPlease be aware that during fast rising glucose, such as after an unannounced meal, this feature, combined with Loop's velocity and retrospective correction effects, may result in a larger dose than your ISF would call for.", comment: "Description of Enhanced AutoBolus toggle."))) {
            Toggle(NSLocalizedString("Enable Enhanced AutoBolus", comment: "Title for Enhanced AutoBolus toggle"), isOn: $isEnhancedAutoBolusEnabled)
                .onChange(of: isEnhancedAutoBolusEnabled) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "applyExperimentalEnhancedAutoBolus")
                }
        }
    }
}

struct EnhancedAutoBolusSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedAutoBolusSelectionView(isEnhancedAutoBolusEnabled: .constant(true))
    }
}
