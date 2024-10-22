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

               Text(NSLocalizedString("Negative Insulin Damper (NID) is used to mitigate the effects of temporarily increased insulin sensitivity. Such increases can result in spending significant times beneath target and eventually going low. Loop may erroneously predict glucose going too high, resulting in excess insulin being delivered. To counteract this, NID acts as a dynamic damper on positive prediced glucose changes. The strength of this damper is controlled by the total predicted rise in glucose due to negative insulin. The greater the amount of negative insulin, the stronger the damper and the bigger the reduction in positive predicted glucose changes.", comment: "Description of Negative Insulin Damper toggle."))
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
