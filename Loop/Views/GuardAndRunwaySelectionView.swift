//
//  GuardAndRunwaySelectionView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

public struct GuardAndRunwaySelectionView: View {
    @Binding var isGuardAndRunwayEnabled: Bool

    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Guard + Runway v2", comment: "Title for guard and runway experiment description, second version"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                Text(NSLocalizedString("Guard + Runway pairs a guard against lows with a little more automatic correction when there is room for it.\n\nAfter a low: for 12 hours after a reading below 70 mg/dL (3.9 mmol/L), while glucose is below 180 mg/dL (10 mmol/L), rises count less toward retrospective correction, so the rebound after treating a low is not taken as a lasting need for more insulin.\n\nVolatility: with no carbs on board, the low guard checks the first two hours of the forecast lowered according to how much glucose has been varying recently, so Loop holds back insulin sooner when glucose is unsettled. The forecast you see and the size of corrections are not lowered.\n\nRunway: at 150 mg/dL (8.3 mmol/L) or above, Loop gives some extra automatic insulin when glucose is calm enough that suspending basal could still take it back before reaching your glucose safety limit. The extra shrinks as carbs on board rise, and stops at 20 g.\n\nNew in version 2: the volatility band only affects the low guard, and the runway fades out with carbs instead of stopping at any carbs.\n\nYour correction range, manual bolus recommendations and glucose safety limit are unchanged. This experiment has been evaluated in simulation and in replays of real data, not yet by people using it.", comment: "Description of Guard + Runway experiment, second version."))
                    .foregroundColor(.secondary)
                Divider()

                Toggle(NSLocalizedString("Enable Guard + Runway v2", comment: "Title for Guard + Runway toggle, second version"), isOn: $isGuardAndRunwayEnabled)
                    .padding(.top, 20)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuardAndRunwaySelectionView_Previews: PreviewProvider {
    static var previews: some View {
        GuardAndRunwaySelectionView(isGuardAndRunwayEnabled: .constant(true))
    }
}
