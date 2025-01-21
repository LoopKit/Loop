//
//  CarbBolusSelectionView.swift
//  Loop
//
//  Created by Moti Nisenson-Ken on 14/01/2025.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//


import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

public struct CarbBolusSelectionView: View {
    @AppStorage(UserDefaults.Key.CarbEntryExcluded.rawValue) var isCarbEntryExcluded = false
    @AppStorage(UserDefaults.Key.CobCorrectionExcluded.rawValue) var isCobCorrectionExcluded = false
    @AppStorage(UserDefaults.Key.BgCorrectionExcluded.rawValue) var isBgCorrectionExcluded = false
    
    public var body: some View {
        
        ScrollView {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Carb Bolus Recommendation", comment: "Title for carb bolus recommendation description"))
                    .font(.headline)
                    .padding(.bottom, 20)

                Divider()

                Text(NSLocalizedString("When bolusing for carbs one can decide which elements to exclude. The toggles below enable one to not bolus for the Carb Entry, or to not give COB or BG corrections. When these are relevant an extra Exclusions row will appear in the Recommendation Breakdown reducing the overall bolus. Rows included in the Exclusions calculated are grayed out. The excluded amount may be smaller than expected, as negative insulin from other rows can still apply.", comment: "carb bolus recommendation options description"))
                    .foregroundColor(.secondary)
                Divider()

                Toggle(NSLocalizedString("Carb Entry Excluded", comment: "Title for Carb Entry Excluded toggle"), isOn: $isCarbEntryExcluded)
                    .padding(.top, 20)

                Toggle(NSLocalizedString("COB Correction Excluded", comment: "Title for COB Correction Excluded toggle"), isOn: $isCobCorrectionExcluded)
                    .padding(.top, 20)
                
                Toggle(NSLocalizedString("BG Correction Excluded", comment: "Title for BG Correction Excluded toggle"), isOn: $isBgCorrectionExcluded)
                    .padding(.top, 20)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
}

extension UserDefaults {
    fileprivate enum Key: String {
        case CarbEntryExcluded = "com.loopkit.underDevelopment.carbBolus.carbyEntryExcluded"
        case CobCorrectionExcluded = "com.loopkit.underDevelopment.carbBolus.correctionExcluded"
        case BgCorrectionExcluded = "com.loopkit.underDevelopment.carbBolus.bgCorrectionExcluded"
    }
    
    var carbBolusCarbEntryExcluded : Bool {
        get {
            bool(forKey: Key.CarbEntryExcluded.rawValue) as Bool
        }
        set {
            set(newValue, forKey: Key.CarbEntryExcluded.rawValue)
        }
    }
    
    var carbBolusCobCorrectionExcluded : Bool {
        get {
            bool(forKey: Key.CobCorrectionExcluded.rawValue) as Bool
        }
        set {
            set(newValue, forKey: Key.CobCorrectionExcluded.rawValue)
        }
    }
    
    var carbBolusBgCorrectionExcluded: Bool {
        get {
            bool(forKey: Key.BgCorrectionExcluded.rawValue) as Bool
        }
        set {
            set(newValue, forKey: Key.BgCorrectionExcluded.rawValue)
        }
    }
}

struct CarbBolusSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        CarbBolusSelectionView()
    }
}

