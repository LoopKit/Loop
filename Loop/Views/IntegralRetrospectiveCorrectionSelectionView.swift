//
//  IntegralRetrospectiveCorrectionSelectionView.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-04.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//
import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

public struct IntegralRetrospectiveCorrectionSelectionView: View {
    @Binding var isIntegralRetrospectiveCorrectionEnabled: Bool
    
    public init(isIntegralRetrospectiveCorrectionEnabled: Binding<Bool>) {
        self._isIntegralRetrospectiveCorrectionEnabled = isIntegralRetrospectiveCorrectionEnabled
    }
    
    public var body: some View {
        List {
            retrospectiveCorrectionSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("Integral")
                        .font(.headline)
                    Text("Retrospective Correction")
                        .font(.subheadline)
                }
            }
        }
    }
    
    private var retrospectiveCorrectionSection: some View {
        VStack {
            DescriptiveText(label: NSLocalizedString("Integral Retrospective Correction (IRC) is an advanced control technique applied to glucose forecasting based on the history of discrepancies between predicted and actual glucose levels. The predictions are made using carbohydrate and insulin data. When enabled, IRC adjusts insulin delivery in response to consistent patterns: it increases insulin delivery when glucose levels consistently measure higher than expected, and decreases it when glucose levels are consistently lower than expected. IRC uses a proportional-integral-differential (PID) controller that adjusts insulin recommendations based on immediate, accumulated, and rate of change discrepancies. This provides a more adaptive and responsive control compared to standard retrospective correction. However, it's important to know that the effectiveness of IRC will heavily depend on the accuracy of your insulin sensitivity, carbohydrate ratios, and basal rates settings. While IRC can improve glucose management in cases of consistent discrepancies, please note that it might potentially lead to more aggressive corrections.", comment: "Description of Integral Retrospective Correction toggle."), color: .black)
            Section() {
                Toggle(NSLocalizedString("Integral Retrospective Correction", comment: "Title for Integral Retrospective Correction toggle"), isOn: $isIntegralRetrospectiveCorrectionEnabled)
                    .onChange(of: isIntegralRetrospectiveCorrectionEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "isExperimentalIntegralRetrospectiveCorrectionEnabled")
                    }
            }
        }
    }
}

struct EnhancedAutoBolusSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        IntegralRetrospectiveCorrectionSelectionView(isIntegralRetrospectiveCorrectionEnabled: .constant(true))
    }
}
