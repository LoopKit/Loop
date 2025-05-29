//
//  DisableRetrospectiveCorrectionSelectionView.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-04.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

public struct DisableRetrospectiveCorrectionSelectionView: View {
    @Binding var isDisableRetrospectiveCorrectionEnabled: Bool
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Disable Retrospective Correction", comment: "Title for disable retrospective correction"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                Text(NSLocalizedString("This toggle allows the complete disabling of any form of retrospective correction (standard or integral).\n\nDisabling the retrospective correction can be particularly useful in specific scenarios, such as when setting or re-evaluating insulin sensitivity factors and carbohydrate ratios.\n\nThe change will take effect in the next 5-minute loop.", comment: "Description of Disable Retrospective Correction toggle."))
                    .foregroundColor(.secondary)
                Divider()

                Toggle(NSLocalizedString("Disable Retrospective Correction", comment: "Title for Disable Retrospective Correction toggle"), isOn: $isDisableRetrospectiveCorrectionEnabled)
                    .padding(.top, 20)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
}

struct DisableRetrospectiveCorrectionSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DisableRetrospectiveCorrectionSelectionView(isDisableRetrospectiveCorrectionEnabled: .constant(true))
    }
}
