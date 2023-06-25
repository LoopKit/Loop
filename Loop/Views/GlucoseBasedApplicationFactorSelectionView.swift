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
    var automaticDosingStrategy: AutomaticDosingStrategy

    public init(isGlucoseBasedApplicationFactorEnabled: Binding<Bool>, automaticDosingStrategy: AutomaticDosingStrategy) {
        self.automaticDosingStrategy = automaticDosingStrategy
        self._isGlucoseBasedApplicationFactorEnabled = isGlucoseBasedApplicationFactorEnabled
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Glucose Based Partial Application", comment: "Title for glucose based partial application experiment description"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                if automaticDosingStrategy == .automaticBolus {
                    Text(NSLocalizedString("Loop normally gives 40% of your predicted insulin needs each dosing cycle.\n\nWhen the Glucose Based Partial Application experiment is enabled, Loop will vary the percentage of recommended bolus delivered each cycle with glucose level.\n\nNear correction range, it will use 20% (similar to Temp Basal), and gradually increase to a maximum of 80% at high glucose (200 mg/dL, 11.1 mmol/L).\n\nPlease be aware that during fast rising glucose, such as after an unannounced meal, this feature, combined with velocity and retrospective correction effects, may result in a larger dose than your ISF would call for.", comment: "Description of Glucose Based Partial Application toggle."))
                        .foregroundColor(.secondary)
                    Divider()

                    HStack {
                        Toggle(NSLocalizedString("Enable Glucose Based Partial Application", comment: "Title for Glucose Based Partial Application toggle"), isOn: $isGlucoseBasedApplicationFactorEnabled)
                        Spacer()
                    }
                    .padding(.top, 20)
                } else {
                    Text(NSLocalizedString("This option only applies when Loop's Dosing Strategy is set to Automatic Bolus.", comment: "String shown when glucose based partial application cannot be enabled because dosing strategy is not set to Automatic Bolus"))
                }
            }
            .padding()
            .onChange(of: isGlucoseBasedApplicationFactorEnabled) { newValue in
                UserDefaults.standard.glucoseBasedApplicationFactorEnabled = newValue
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GlucoseBasedApplicationFactorSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            GlucoseBasedApplicationFactorSelectionView(isGlucoseBasedApplicationFactorEnabled: .constant(true), automaticDosingStrategy: .automaticBolus)
        }
    }
}
