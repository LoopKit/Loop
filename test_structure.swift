//
//  CarbEntryView.swift
//  Loop
//
//  Created by Noah Brauner on 7/19/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopUI
import HealthKit
import UIKit
import os.log

struct CarbEntryView: View, HorizontalSizeClassOverride {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismissAction) private var dismiss

    @ObservedObject var viewModel: CarbEntryViewModel
        
    @State private var expandedRow: Row?
    @State private var isAdvancedAnalysisExpanded: Bool = false
    @State private var showHowAbsorptionTimeWorks = false
    @State private var showAddFavoriteFood = false
    @State private var showingAICamera = false
    @State private var showingAISettings = false
    
    // MARK: - Row enum
    enum Row {
        case amountConsumed, time, foodType, absorptionTime, favoriteFoodSelection, detailedFoodBreakdown, advancedAnalysis
    }
    
    private let isNewEntry: Bool

    init(viewModel: CarbEntryViewModel) {
        self.viewModel = viewModel
        self.isNewEntry = viewModel.originalCarbEntry == nil
        if viewModel.shouldBeginEditingQuantity {
            self._expandedRow = State(initialValue: .amountConsumed)
        } else {
            self._expandedRow = State(initialValue: nil)
        }
    }
    
    var body: some View {
        if isNewEntry {
            NavigationView {
                let title = NSLocalizedString("carb-entry-title-add", value: "Add Carb Entry", comment: "The title of the view controller to create a new carb entry")

// Test compilation of structure
struct TestCarbEntry: View {
    var body: some View {
        Text("Test")
    }
}
