//
//  AutoBolusCarbsSelectionView.swift
//  Loop
//
//  Created by Moti Nisenson-Ken on 23/12/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

public struct AutoBolusCarbsSelectionView: View {
    @Binding var isAutoBolusCarbsEnabled: Bool
    @Binding var autoBolusCarbsActiveByDefault: Bool
    
    public var body: some View {
        
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Auto-Bolus Carbs", comment: "Title for auto-bolus carbs experiment description"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                Text(String(format: NSLocalizedString("Auto-Bolus Carbs (ABC) is a modification of how Loop corrects each loop cycle. When enabled and active, Loop will check how much insulin is needed to cover COB (similar to doing a manual bolus but without correcting for BG). If this amount is greater than the usual correction, a bolus for that amount will be given. Overrides can also be used to activate or deactivate. When ABC is enabled and active a %@ will appear beside Active Carbohydrates on the status screen.", comment: "Description of Auto-Bolus Carbs toggles."), "🔸"))
                    .foregroundColor(.secondary)
                Divider()

                Toggle(NSLocalizedString("Auto-Bolus Carbs Enabled", comment: "Title for Auto-Bolus Carbs Enabled toggle"), isOn: $isAutoBolusCarbsEnabled)
                    .onChange(of: isAutoBolusCarbsEnabled) { newValue in
                        UserDefaults.standard.autoBolusCarbsEnabled = newValue
                    }
                    .padding(.top, 20)
                
                Toggle(NSLocalizedString("Auto-Bolus Carbs Active by Default", comment: "Title for Auto-Bolus Carbs Active by Default toggle"), isOn: $autoBolusCarbsActiveByDefault)
                    .onChange(of: autoBolusCarbsActiveByDefault) { newValue in
                        UserDefaults.standard.autoBolusCarbsActiveByDefault = newValue
                    }
                    .padding(.top, 20)
                // in the future consider disabling unless available
//                    .disabled(isAutoBolusCarbsAvailable)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
}

struct AutoBolusCarbsSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        AutoBolusCarbsSelectionView(isAutoBolusCarbsEnabled: .constant(true), autoBolusCarbsActiveByDefault: .constant(false))
    }
}
