//
//  FavoriteFoodInsightsView.swift
//  Loop
//
//  Created by Noah Brauner on 7/15/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import LoopAlgorithm

struct FavoriteFoodInsightsView: View {
    @StateObject private var viewModel: FavoriteFoodInsightsViewModel
    
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismiss) private var dismiss
    
    @State private var isInteractingWithChart = false
    
    @State private var showHowCarbEffectsWorks = false

    let presentedAsSheet: Bool
    
    init(viewModel: FavoriteFoodInsightsViewModel, presentedAsSheet: Bool = true) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.presentedAsSheet = presentedAsSheet
    }
    
    var body: some View {
        if presentedAsSheet {
            NavigationView {
                content
                    .toolbar {
                        dismissButton
                    }
            }
        }
        else {
            content
                .insetGroupedListStyle()
        }
    }
    
    private var content: some View {
        List {
            historicalCarbEntriesSection
            historicalDataReviewSection
        }
        .padding(.top, -28)
        .navigationTitle("Favorite Food Insights")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHowCarbEffectsWorks) {
            HowCarbEffectsWorksView()
        }
    }

    private var historicalCarbEntriesSection: some View {
        Section {
            if let carbEntry = viewModel.carbEntry {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Spacer()
                        
                        let isAtStart = viewModel.carbEntryIndex == 0
                        Button(action: {
                            guard !isAtStart else { return }
                            viewModel.carbEntryIndex -= 1
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title3.bold())
                        }
                        .disabled(isAtStart)
                        .opacity(isAtStart ? 0.4 : 1)
                        .buttonStyle(BorderlessButtonStyle())
                        .contentShape(Rectangle())
                        
                        Text("Viewing entry \(viewModel.carbEntryIndex + 1) of \(viewModel.carbEntries.count)")
                            .font(.headline)
                        
                        let isAtEnd = viewModel.carbEntryIndex >= viewModel.carbEntries.count - 1
                        Button(action: {
                            guard !isAtEnd else { return }
                            viewModel.carbEntryIndex += 1
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.title3.bold())
                        }
                        .disabled(isAtEnd)
                        .opacity(isAtEnd ? 0.4 : 1)
                        .buttonStyle(BorderlessButtonStyle())
                        .contentShape(Rectangle())
                        
                        Spacer()
                    }
                    
                    if let formattedCarbQuantity = viewModel.carbFormatter.string(from: carbEntry.quantity), let absorptionTime = carbEntry.absorptionTime, let formattedAbsorptionTime = viewModel.absorptionTimeFormatter.string(from: absorptionTime) {
                        let formattedRelativeDate = viewModel.relativeDateFormatter.localizedString(for: carbEntry.startDate, relativeTo: viewModel.now)
                        let formattedDate = viewModel.dateFormater.string(from: carbEntry.startDate)
                        
                        let rows: [(field: String, value: String)] = [
                            ("Food", viewModel.food.title),
                            ("Carb Quantity",  formattedCarbQuantity),
                            ("Date", "\(formattedDate) - \(formattedRelativeDate)"),
                            ("Absorption Time", "\(formattedAbsorptionTime)")
                        ]
                        
                        ForEach(rows, id: \.field) { row in
                            HStack(alignment: .top) {
                                Text(row.field)
                                    .font(.subheadline)
                                Spacer()
                                Text(row.value)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    private var historicalDataReviewSection: some View {
        Section(header: historicalDataReviewHeader) {
            FavoriteFoodsInsightsChartsView(viewModel: viewModel, showHowCarbEffectsWorks: $showHowCarbEffectsWorks)
        }
    }
    
    private var historicalDataReviewHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text("Historical Data")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(viewModel.dateIntervalFormatter.string(from: viewModel.startDate, to: viewModel.endDate))
            }
            
            Spacer()
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 20, leading: 4, bottom: 10, trailing: 4))
    }
    
    private var dismissButton: some View {
        Button(action: {
            dismiss()
        }) {
            Text("Done")
        }
    }
}
