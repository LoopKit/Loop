//
//  SlowRetrospectiveCorrectionSelectionView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

public struct SlowRetrospectiveCorrectionSelectionView: View {
    @Binding var isSlowRetrospectiveCorrectionEnabled: Bool

    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Slow Retrospective Correction", comment: "Title for slow retrospective correction experiment description"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                Text(NSLocalizedString("Slow Retrospective Correction looks back over the last 3 days for a lasting difference between what your settings expect and what your glucose did.\n\nWhen glucose has kept rising more than Loop's forecasts explained, Loop doses as if your insulin sensitivity were lower, giving more insulin. When glucose has kept falling more than expected, it gives less. The adjustment builds over about a day and stays between 0.7 and 1.3 times your insulin sensitivity.\n\nIt applies to the forecast, automatic dosing and bolus recommendations. Meals eaten without a carb entry in those 3 days look like unexplained rises and lead to more insulin. With less than 3 days of data it adjusts less.\n\nThis experiment has been evaluated in simulation and in replays of real data, not yet by people using it.", comment: "Description of Slow Retrospective Correction experiment."))
                    .foregroundColor(.secondary)
                Divider()

                Toggle(NSLocalizedString("Enable Slow Retrospective Correction", comment: "Title for Slow Retrospective Correction toggle"), isOn: $isSlowRetrospectiveCorrectionEnabled)
                    .padding(.top, 20)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SlowRetrospectiveCorrectionSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        SlowRetrospectiveCorrectionSelectionView(isSlowRetrospectiveCorrectionEnabled: .constant(true))
    }
}
