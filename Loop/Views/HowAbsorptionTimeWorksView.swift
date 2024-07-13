//
//  HowAbsorptionTimeWorksView.swift
//  Loop
//
//  Created by Noah Brauner on 7/28/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct HowAbsorptionTimeWorksView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Choose a longer absorption time for larger meals, or those containing fats and proteins. This is only guidance to the algorithm and need not be exact.", comment: "Carb entry section footer text explaining absorption time")
                }
            }
            .navigationTitle("Absorption Time")
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
