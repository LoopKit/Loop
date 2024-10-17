//
//  NegativeInsulinDamperSelectionView.swift
//  Loop
//
//  Created by Moti Nisenson-Ken on 16/10/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//
import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

struct NegativeInsulinDamperSelectionView: View {
   @Binding var isNegativeInsulinDamperEnabled: Bool
   
   public var body: some View {
       ScrollView {
           VStack(spacing: 10) {
               Text(NSLocalizedString("Negative Insulin Damper", comment: "Title for negative insulin damper experiment description"))
                   .font(.headline)
                   .padding(.bottom, 20)

               Divider()

               Text(NSLocalizedString("Negative Insulin Damper (NID) is used to mitigate the effects negative insulin have on predicted glucose levels. After spending significant time beneath the correction range, there may be a build up of negative insulin which will result in larger predicted glucose values, and subsequently may result in too much insulin being given by Loop. NID reduces the magnitude of these predictions. The larger the total predicted rise in glucose due to negative insulin, the greater the reduction will be.", comment: "Description of Negative Insulin Damper toggle."))
                   .foregroundColor(.secondary)
               Divider()

               Toggle(NSLocalizedString("Enable Negative Insulin Damper", comment: "Title for Negative Insulin Damper toggle"), isOn: $isNegativeInsulinDamperEnabled)
                   .onChange(of: isNegativeInsulinDamperEnabled) { newValue in
                       UserDefaults.standard.negativeInsulinDamperEnabled = newValue
                   }
                   .padding(.top, 20)
           }
           .padding()
       }
       .navigationBarTitleDisplayMode(.inline)
   }

   struct NegativeInsulinDamperSelectionView_Previews: PreviewProvider {
       static var previews: some View {
           NegativeInsulinDamperSelectionView(isNegativeInsulinDamperEnabled: .constant(true))
       }
   }
}
