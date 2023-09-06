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
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Integral Retrospective Correction", comment: "Title for integral retrospective correction experiment description"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                Text(NSLocalizedString("Integral Retrospective Correction (IRC) is an extension of the standard Retrospective Correction (RC) algorithm component in Loop, which adjusts the forecast based on the history of discrepancies between predicted and actual glucose levels.\n\nIn contrast to RC, which looks at discrepancies over the last 30 minutes, with IRC, the history of discrepancies adds up over time. So continued positive discrepancies over time will result in increased dosing. If the discrepancies are negative over time, Loop will reduce dosing further.", comment: "Description of Integral Retrospective Correction toggle."))
                    .foregroundColor(.secondary)
                Divider()

                Toggle(NSLocalizedString("Enable Integral Retrospective Correction", comment: "Title for Integral Retrospective Correction toggle"), isOn: $isIntegralRetrospectiveCorrectionEnabled)
                    .onChange(of: isIntegralRetrospectiveCorrectionEnabled) { newValue in
                        UserDefaults.standard.integralRetrospectiveCorrectionEnabled = newValue
                    }
                    .padding(.top, 20)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
}

struct IntegralRetrospectiveCorrectionSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        IntegralRetrospectiveCorrectionSelectionView(isIntegralRetrospectiveCorrectionEnabled: .constant(true))
    }
}
