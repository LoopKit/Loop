//
//  HowCarbEffectsWorksView.swift
//  Loop
//
//  Created by Noah Brauner on 7/25/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct HowCarbEffectsWorksView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Observed changes in glucose, subtracting changes modeled from insulin delivery, can be used to estimate carbohydrate absorption.", comment: "Section explaining carb effects chart")
                }
            }
            .navigationTitle("Glucose Change Chart")
            .toolbar {
                dismissButton
            }
        }
    }
    
    private var dismissButton: some View {
        Button(action: dismiss.callAsFunction) {
            Text("Close")
        }
    }
}
