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
    @State private var isFoodSearchEnabled = UserDefaults.standard.foodSearchEnabled
    @State private var showAbsorptionReasoning = false
    
    // MARK: - Row enum
    enum Row: Hashable {
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
                content
                    .navigationBarTitle(title, displayMode: .inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            dismissButton
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            continueButton
                        }
                    }
                
            }
            .navigationViewStyle(StackNavigationViewStyle())
        } else {
            content
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        continueButton
                    }
                }
        }
    }
    
    private var content: some View {
        ZStack {
            Color(.systemGroupedBackground)
                // Avoid interfering with status/navigation bar insets on newer devices
                .ignoresSafeArea(.container, edges: .bottom)
                .onTapGesture {
                    // Dismiss keyboard when tapping background
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            
            ScrollView {
                warningsCard

                mainCard
                    .padding(.top, 8)
                
                continueActionButton
                
                if isNewEntry {
                    favoriteFoodsCard
                }
                
                let isBolusViewActive = Binding(get: { viewModel.bolusViewModel != nil }, set: { _, _ in viewModel.bolusViewModel = nil })
                NavigationLink(destination: bolusView, isActive: isBolusViewActive) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibility(hidden: true)
            }
        }
        .alert(item: $viewModel.alert, content: alert(for:))
        .sheet(isPresented: $showAddFavoriteFood, onDismiss: clearExpandedRow) {
            let suggestedName = viewModel.selectedFoodProduct?.productName
            AddEditFavoriteFoodView(carbsQuantity: viewModel.carbsQuantity, foodType: viewModel.foodType, absorptionTime: viewModel.absorptionTime, suggestedName: suggestedName, onSave: onFavoriteFoodSave(_:))
        }
        .sheet(isPresented: $showHowAbsorptionTimeWorks) {
            HowAbsorptionTimeWorksView()
        }
        .sheet(isPresented: $showingAICamera) {
            AICameraView(
                onFoodAnalyzed: { result, capturedImage in
                    Task { @MainActor in
                        handleAIFoodAnalysis(result)
                        viewModel.capturedAIImage = capturedImage
                        showingAICamera = false
                    }
                },
                onCancel: {
                    showingAICamera = false
                }
            )
        }
        .sheet(isPresented: $showingAISettings) {
            AISettingsView()
        }
        .onAppear {
            isFoodSearchEnabled = UserDefaults.standard.foodSearchEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Update state when UserDefaults changes (e.g., from Settings screen)
            let currentSetting = UserDefaults.standard.foodSearchEnabled
            if currentSetting != isFoodSearchEnabled {
                isFoodSearchEnabled = currentSetting
            }
        }
    }
    
    private var mainCard: some View {
        VStack(spacing: 10) {
            let amountConsumedFocused: Binding<Bool> = Binding(get: { expandedRow == .amountConsumed }, set: { expandedRow = $0 ? .amountConsumed : nil })
            let timerFocused: Binding<Bool> = Binding(get: { expandedRow == .time }, set: { expandedRow = $0 ? .time : nil })
            let foodTypeFocused: Binding<Bool> = Binding(get: { expandedRow == .foodType }, set: { expandedRow = $0 ? .foodType : nil })
            let absorptionTimeFocused: Binding<Bool> = Binding(get: { expandedRow == .absorptionTime }, set: { expandedRow = $0 ? .absorptionTime : nil })
            
            CarbQuantityRow(quantity: $viewModel.carbsQuantity, isFocused: amountConsumedFocused, title: NSLocalizedString("Amount Consumed", comment: "Label for carb quantity entry row on carb entry screen"), preferredCarbUnit: viewModel.preferredCarbUnit)
            
            // Food search section - moved up from bottom
            if isNewEntry && isFoodSearchEnabled {
                CardSectionDivider()
                
                VStack(spacing: 16) {
                    // Section header
                    HStack {
                        Text("Search for Food")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // AI Settings button
                        Button(action: {
                            showingAISettings = true
                        }) {
                            Image(systemName: "gear")
                                .foregroundColor(.secondary)
                                .font(.system(size: 24))
                        }
                        .accessibilityLabel("AI Settings")
                    }
                    
                    // Search bar with barcode and AI camera buttons
                    FoodSearchBar(
                        searchText: $viewModel.foodSearchText,
                        onBarcodeScanTapped: {
                            // Barcode scanning is handled by FoodSearchBar's sheet presentation
                        },
                        onAICameraTapped: {
                            // Handle AI camera
                            showingAICamera = true
                        }
                    )
                    
                    // Search results
                    if viewModel.isFoodSearching || viewModel.showingFoodSearch || !viewModel.foodSearchResults.isEmpty {
                        FoodSearchResultsView(
                            searchResults: viewModel.foodSearchResults,
                            isSearching: viewModel.isFoodSearching,
                            errorMessage: viewModel.foodSearchError,
                            onProductSelected: { product in
                                viewModel.selectFoodProduct(product)
                            }
                        )
                    }
                }
                .onAppear {
                    // Setup food search observers when the view appears
                    viewModel.setupFoodSearchObservers()
                }
                
                CardSectionDivider()
            }
            
            // Food-related rows (only show if food search is enabled)
            if isFoodSearchEnabled {
                // Always show servings row when food search is enabled
                ServingsDisplayRow(
                    servings: $viewModel.numberOfServings, 
                    servingSize: viewModel.selectedFoodServingSize,
                    selectedFoodProduct: viewModel.selectedFoodProduct
                )
                .id("servings-\(viewModel.selectedFoodServingSize ?? "none")")
                .onChange(of: viewModel.numberOfServings) { newServings in
                    // Force recalculation if we have a selected food product
                    if let selectedFood = viewModel.selectedFoodProduct {
                        let expectedCarbs = (selectedFood.carbsPerServing ?? selectedFood.nutriments.carbohydrates) * newServings
                        
                        // Force update the carbs quantity if it doesn't match
                        if abs((viewModel.carbsQuantity ?? 0) - expectedCarbs) > 0.01 {
                            viewModel.carbsQuantity = expectedCarbs
                        }
                    }
                }
            
                // Clean product information for scanned items
                if let selectedFood = viewModel.selectedFoodProduct {
                    VStack(spacing: 12) {
                        // Product image at the top (works for both barcode and AI scanned images)
                        if let capturedImage = viewModel.capturedAIImage {
                            // Show AI captured image
                            Image(uiImage: capturedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 90)
                                .clipped()
                                .cornerRadius(12)
                        } else if let imageURL = selectedFood.imageFrontURL ?? selectedFood.imageURL, !imageURL.isEmpty {
                            // Show barcode product image from URL
                            AsyncImage(url: URL(string: imageURL)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 90)
                                    .clipped()
                                    .cornerRadius(12)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                                    .frame(width: 120, height: 90)
                                    .overlay(
                                        VStack(spacing: 4) {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                            Text("Loading...")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    )
                            }
                        }
                        
                        // Product name with favorite heart (centered as a unit)
                        ZStack {
                            // Centered content
                            HStack(spacing: 8) {
                                Text(shortenedTitle(selectedFood.displayName))
                                    .font(.headline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Button(action: { toggleQuickFavorite(for: selectedFood) }) {
                                    Image(systemName: isQuickFavorited(selectedFood) ? "heart.fill" : "heart")
                                        .foregroundColor(isQuickFavorited(selectedFood) ? .red : Color(UIColor.tertiaryLabel))
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)

                            // Invisible spacers to balance left/right so ZStack centers correctly
                            HStack {
                                Color.clear.frame(width: 1)
                                Spacer()
                                Color.clear.frame(width: 1)
                            }
                        }
                    
                        // Package serving size (only show "Package Serving Size:" prefix for barcode scans)
                        Text(selectedFood.dataSource == .barcodeScan ? "Package Serving Size: \(selectedFood.servingSizeDisplay)" : selectedFood.servingSizeDisplay)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Animated nutrition circles right below the product info
                    VStack(spacing: 8) {
                        // Horizontal scrollable nutrition indicators
                        HStack(alignment: .center) {
                            Spacer()
                            HStack(alignment: .center, spacing: 12) {
                                // Use AI analysis result if available, otherwise fall back to selected food
                                let aiResult = viewModel.lastAIAnalysisResult
                                
                                // Precompute nutrient values outside of ViewBuilder heavy logic
                                let valuesTuple = computeDisplayedMacros(
                                    selectedFood: selectedFood,
                                    aiResult: aiResult,
                                    numberOfServings: viewModel.numberOfServings,
                                    excluded: viewModel.excludedAIItemIndices
                                )
                                let carbsValue = valuesTuple.carbs
                                let caloriesValue = valuesTuple.calories
                                let fatValue = valuesTuple.fat
                                let fiberValue = valuesTuple.fiber
                                let proteinValue = valuesTuple.protein

                                let fallbackCalories = (proteinValue ?? 0) * 4 + (fatValue ?? 0) * 9 + carbsValue * 4
                                let caloriesForTargets: Double? = {
                                    if let caloriesValue, caloriesValue > 0 {
                                        return caloriesValue
                                    }
                                    return fallbackCalories > 0 ? fallbackCalories : nil
                                }()
                                // Derive per-meal targets using observed carbs as the anchor
                                let balancedTargets = computeBalancedTargets(
                                    carbs: carbsValue,
                                    protein: proteinValue,
                                    fat: fatValue,
                                    calories: caloriesForTargets
                                )

                                let carbTarget = max(balancedTargets?.carbs ?? max(carbsValue, 1), 1)
                                
                                // Carbohydrates (first)
                                NutritionCircle(
                                    value: carbsValue,
                                    unit: "g",
                                    label: "Carbs",
                                    color: Color(red: 0.4, green: 0.7, blue: 1.0), // Light blue
                                    maxValue: carbTarget
                                )
                                
                                // Calories (second)
                                let caloriesAmount = caloriesValue ?? balancedTargets?.calories ?? 0
                                if caloriesAmount > 0 {
                                    let calorieTarget = max(balancedTargets?.calories ?? max(caloriesAmount, 1), 1)
                                    NutritionCircle(
                                        value: caloriesAmount,
                                        unit: "cal",
                                        label: "Calories",
                                        color: Color(red: 0.5, green: 0.8, blue: 0.4), // Green
                                        maxValue: calorieTarget
                                    )
                                }
                                
                                // Fat (third)
                                if let fatTarget = balancedTargets?.fat, fatTarget > 0 {
                                    let fatAmount = max(fatValue ?? 0, 0)
                                    NutritionCircle(
                                        value: fatAmount,
                                        unit: "g",
                                        label: "Fat", 
                                        color: Color(red: 1.0, green: 0.8, blue: 0.2), // Golden yellow
                                        maxValue: max(fatTarget, 1)
                                    )
                                } else if let fat = fatValue, fat > 0 {
                                    NutritionCircle(
                                        value: fat,
                                        unit: "g",
                                        label: "Fat", 
                                        color: Color(red: 1.0, green: 0.8, blue: 0.2), // Golden yellow
                                        maxValue: 20.0 // Typical fat portion
                                    )
                                }
                                
                                // Fiber (fourth)
                                if let fiberTarget = balancedTargets?.fiber, fiberTarget > 0 {
                                    let fiberAmount = max(fiberValue ?? 0, 0)
                                    NutritionCircle(
                                        value: fiberAmount,
                                        unit: "g", 
                                        label: "Fiber",
                                        color: Color(red: 0.6, green: 0.4, blue: 0.8), // Purple
                                        maxValue: max(fiberTarget, 1)
                                    )
                                } else if let fiber = fiberValue, fiber > 0 {
                                    NutritionCircle(
                                        value: fiber,
                                        unit: "g", 
                                        label: "Fiber",
                                        color: Color(red: 0.6, green: 0.4, blue: 0.8), // Purple
                                        maxValue: 10.0 // Typical daily fiber portion
                                    )
                                }
                                
                                // Protein (fifth)
                                if let proteinTarget = balancedTargets?.protein, proteinTarget > 0 {
                                    let proteinAmount = max(proteinValue ?? 0, 0)
                                    NutritionCircle(
                                        value: proteinAmount,
                                        unit: "g", 
                                        label: "Protein",
                                        color: Color(red: 1.0, green: 0.4, blue: 0.4), // Coral/red
                                        maxValue: max(proteinTarget, 1)
                                    )
                                } else if let protein = proteinValue, protein > 0 {
                                    NutritionCircle(
                                        value: protein,
                                        unit: "g", 
                                        label: "Protein",
                                        color: Color(red: 1.0, green: 0.4, blue: 0.4), // Coral/red
                                        maxValue: 30.0 // Typical protein portion
                                    )
                                }
                            }
                            Spacer()
                        }
                        .frame(height: 90) // Increased height to prevent clipping
                        .id("nutrition-circles-\(viewModel.numberOfServings)")
                        
                        // Confidence line (AI only)
                        Group {
                            if let ai = viewModel.lastAIAnalysisResult {
                                let pct = computeConfidencePercent(from: ai, servings: viewModel.numberOfServings)
                                HStack(spacing: 6) {
                                    Text("Confidence:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(pct)%")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(confidenceBadgeColor(pct))
                                        .foregroundColor(confidenceColor(pct))
                                        .clipShape(Capsule())
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                }
                
                // Concise AI Analysis Notes (moved below nutrition circles)
                if let aiResult = viewModel.lastAIAnalysisResult {
                    VStack(spacing: 8) {
                        // Detailed Food Breakdown (expandable)
                        if !aiResult.foodItemsDetailed.isEmpty {
                            detailedFoodBreakdownSection(aiResult: aiResult)
                        }
                        
                        // Portion estimation method (expandable)
                        // Portion estimation method (expandable)
                        let trimmedPortion = aiResult.portionAssessmentMethod?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let portionSummary = trimmedPortion.isEmpty ? fallbackPortionSummary(aiResult: aiResult) : trimmedPortion
                        if !portionSummary.isEmpty {
                            let pct = computeConfidencePercent(from: aiResult, servings: viewModel.numberOfServings)
                            let confidenceLine = pct < 60 ? "Confidence: \(pct)% – treat as estimate" : "Confidence: \(pct)%"
                            let noteContent = portionSummary + "\n\n" + confidenceLine
                            ExpandableNoteView(
                                icon: "ruler",
                                iconColor: .blue,
                                title: "Portions & Servings:",
                                content: noteContent,
                                backgroundColor: Color(.systemBlue).opacity(0.08)
                            )
                        }
                        
                        // Diabetes considerations (expandable)
                        if let diabetesNotes = aiResult.diabetesConsiderations, !diabetesNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ExpandableNoteView(
                                icon: "drop.fill",
                                iconColor: .red,
                                title: "Diabetes Note:",
                                content: diabetesNotes,
                                backgroundColor: Color(.systemRed).opacity(0.08)
                            )
                        }
                        
                        // Advanced dosing information (conditional on settings)
                        if UserDefaults.standard.advancedDosingRecommendationsEnabled {
                            advancedAnalysisSection(aiResult: aiResult)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            } // End food search enabled section

            CardSectionDivider()
            
            DatePickerRow(date: $viewModel.time, isFocused: timerFocused, minimumDate: viewModel.minimumDate, maximumDate: viewModel.maximumDate)
            
            CardSectionDivider()
            
            FoodTypeRow(foodType: $viewModel.foodType, absorptionTime: $viewModel.absorptionTime, selectedDefaultAbsorptionTimeEmoji: $viewModel.selectedDefaultAbsorptionTimeEmoji, usesCustomFoodType: $viewModel.usesCustomFoodType, absorptionTimeWasEdited: $viewModel.absorptionTimeWasEdited, isFocused: foodTypeFocused, defaultAbsorptionTimes: viewModel.defaultAbsorptionTimes)
            
            CardSectionDivider()
            
            AIAbsorptionTimePickerRow(absorptionTime: $viewModel.absorptionTime, isFocused: absorptionTimeFocused, validDurationRange: viewModel.absorptionRimesRange, isAIGenerated: viewModel.absorptionTimeWasAIGenerated, showHowAbsorptionTimeWorks: $showHowAbsorptionTimeWorks)
                .onReceive(viewModel.$absorptionTimeWasAIGenerated) { isAIGenerated in
                    print("🎯 AIAbsorptionTimePickerRow received isAIGenerated: \(isAIGenerated)")
                }
                .padding(.bottom, 2)

            if let reasoning = viewModel.lastAIAnalysisResult?.absorptionTimeReasoning?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reasoning.isEmpty,
               viewModel.absorptionTimeWasAIGenerated {
                let hoursString = String(format: "%.1f", viewModel.absorptionTime / 3600)
                DisclosureGroup(isExpanded: $showAbsorptionReasoning) {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass.bottomhalf.fill")
                            .foregroundColor(.indigo)
                        Text("Why \(hoursString) hours?")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.indigo)
                    }
                }
                .padding(8)
                .background(Color(.systemIndigo).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            
            // Food Search enablement toggle (only show when Food Search is disabled)
            if !isFoodSearchEnabled {
                CardSectionDivider()
                
                FoodSearchEnableRow(isFoodSearchEnabled: $isFoodSearchEnabled)
                    .padding(.bottom, 2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(CardBackground())
        .padding(.horizontal, 8)
    }
    
    @ViewBuilder
    private var bolusView: some View {
        if let viewModel = viewModel.bolusViewModel {
            BolusEntryView(viewModel: viewModel)
                .environmentObject(displayGlucosePreference)
                .environment(\.dismissAction, dismiss)
        } else {
            EmptyView()
        }
    }
    
    private func clearExpandedRow() {
        self.expandedRow = nil
    }
    
    /// Handle AI food analysis results by converting to food product format
    @MainActor
    private func handleAIFoodAnalysis(_ result: AIFoodAnalysisResult) {
        var enrichedResult = result
        viewModel.ensureAbsorptionTimeForInitialResult(&enrichedResult)
        showAbsorptionReasoning = false

        // Store the detailed AI result for UI display
        viewModel.lastAIAnalysisResult = enrichedResult
        
        // Convert AI result to OpenFoodFactsProduct format for consistency
        let aiProduct = convertAIResultToFoodProduct(enrichedResult)
        
        // Use existing food selection workflow
        viewModel.selectFoodProduct(aiProduct)

        // Set servings carefully to avoid double-scaling
        if enrichedResult.servings > 0 && enrichedResult.servings < 0.95 {
            // Totals already represent the measured portion; keep 1.0 serving
            // Unless we detected a base-serving reconstruction above (medium reference).
            if enrichedResult.servingSizeDescription.localizedCaseInsensitiveContains("medium") {
                // In base-serving mode, use the multiplier as servings
                viewModel.numberOfServings = enrichedResult.servings
            } else {
                viewModel.numberOfServings = 1.0
            }
        } else if enrichedResult.servings >= 0.95 {
            // Use provided servings (≈1 or more)
            viewModel.numberOfServings = enrichedResult.servings
        } else {
            viewModel.numberOfServings = 1.0
        }
        
        // Set dynamic absorption time from AI analysis (works for both Standard and Advanced modes)
        print("🤖 AI ABSORPTION TIME DEBUG:")
        print("🤖 Advanced Dosing Enabled: \(UserDefaults.standard.advancedDosingRecommendationsEnabled)")
        print("🤖 AI Absorption Hours: \(enrichedResult.absorptionTimeHours ?? 0)")
        print("🤖 Current Absorption Time: \(viewModel.absorptionTime)")
        
        if let absorptionHours = enrichedResult.absorptionTimeHours,
           absorptionHours > 0 {
            let absorptionTimeInterval = TimeInterval(absorptionHours * 3600) // Convert hours to seconds
            
            print("🤖 Setting AI absorption time: \(absorptionHours) hours = \(absorptionTimeInterval) seconds")
            
            // Use programmatic flag to prevent observer from clearing AI flag
            viewModel.absorptionEditIsProgrammatic = true
            viewModel.absorptionTime = absorptionTimeInterval
            
            // Set AI flag after a brief delay to ensure observer has completed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                viewModel.absorptionTimeWasAIGenerated = true // Mark as AI-generated for visual indication
                print("🤖 AI absorption time flag set. Flag: \(viewModel.absorptionTimeWasAIGenerated)")
            }
            
        } else {
            print("🤖 AI absorption time conditions not met - not setting absorption time")
        }

        // Soft clamp for obvious slice-based overestimates (initialization only)
        // Applies when description includes "medium" base and portion mentions slices (1–4)
        if enrichedResult.servingSizeDescription.localizedCaseInsensitiveContains("medium") {
            let portionText = (enrichedResult.analysisNotes ?? enrichedResult.servingSizeDescription).lowercased()
            // Extract a small slice count (1-4)
            if portionText.contains("slice") || portionText.contains("slices") {
                if let match = portionText.range(of: "\\b(1|2|3|4)\\b", options: .regularExpression) {
                    let count = Int(portionText[match]) ?? 0
                    var cap: Double = 0
                    switch count {
                    case 1: cap = 0.25
                    case 2: cap = 0.35
                    case 3, 4: cap = 0.50
                    default: break
                    }
                    if cap > 0 {
                        let aiServings = enrichedResult.servings
                        if aiServings > cap {
                            print("🧮 Applying slice-based soft cap: AI=\(aiServings) -> cap=\(cap) for \(count) slice(s)")
                            viewModel.numberOfServings = cap
                        }
                    }
                }
            }
        }
    }
    
    /// Convert AI analysis result to OpenFoodFactsProduct for integration with existing workflow
    private func convertAIResultToFoodProduct(_ result: AIFoodAnalysisResult) -> OpenFoodFactsProduct {
        // Create synthetic ID for AI-generated products
        let aiId = "ai_\(UUID().uuidString.prefix(8))"
        
        // Extract actual food name for the main display, not the portion description
        let displayName = extractFoodNameFromAIResult(result)
        
        // Decide scaling strategy to avoid double-multiplying portions.
        // If AI returned a fractional `servings` (e.g., 0.23 for 35g out of 150g),
        // treat totals as already for the measured portion and DO NOT divide by servings.
        // If servings >= ~0.95 (≈1) or > 1, we compute per‑serving values.
        let aiServings = result.servings
        let useTotalsAsServing = aiServings > 0 && aiServings < 0.95
        #if DEBUG
        print("🧮 AI scaling: servings=\(aiServings), useTotalsAsServing=\(useTotalsAsServing)")
        #endif
        let baseDivisor = useTotalsAsServing ? 1.0 : max(1.0, aiServings)
        let carbsPerServing = result.carbohydrates / baseDivisor
        let proteinPerServing = (result.protein ?? 0) / baseDivisor
        let fatPerServing = (result.fat ?? 0) / baseDivisor
        let caloriesPerServing = (result.calories ?? 0) / baseDivisor
        let fiberPerServing = (result.fiber ?? 0) / baseDivisor
        
        // Create nutriments with per-serving values so they scale correctly
        let nutriments = Nutriments(
            carbohydrates: carbsPerServing,
            proteins: proteinPerServing > 0 ? proteinPerServing : nil,
            fat: fatPerServing > 0 ? fatPerServing : nil,
            calories: caloriesPerServing > 0 ? caloriesPerServing : nil,
            sugars: nil,
            fiber: fiberPerServing > 0 ? fiberPerServing : nil
        )
        
        // Use serving size description for the "Based on" text
        let servingSizeDisplay = result.servingSizeDescription

        // If AI reported a fractional portion multiplier and we also have an implied
        // USDA base like "1 medium <fruit>", prefer base-serving semantics:
        // - nutriments represent per-base-serving (e.g., 1 medium peach ~150g ≈ 15–16g carbs)
        // - numberOfServings encodes the fraction (e.g., 0.25)
        // We approximate base-serving carbs from per-100g if base looks like a medium fruit.
        // This avoids over/under-scaling when rendering the USDA Serving line.
        var adjustedNutriments = nutriments
        var adjustedServings = result.servings
        if result.servings > 0, result.servings < 0.95, servingSizeDisplay.localizedCaseInsensitiveContains("medium") {
            // Reconstruct base-serving (1 medium) by dividing totals by the fractional servings
            let divisor = max(result.servings, 0.01)
            let baseCarbs = result.carbohydrates / divisor
            let baseProtein = (result.protein ?? 0) / divisor
            let baseFat = (result.fat ?? 0) / divisor
            let baseCalories = (result.calories ?? 0) / divisor
            let baseFiber = (result.fiber ?? 0) / divisor
            adjustedNutriments = Nutriments(
                carbohydrates: baseCarbs,
                proteins: baseProtein > 0 ? baseProtein : nil,
                fat: baseFat > 0 ? baseFat : nil,
                calories: baseCalories > 0 ? baseCalories : nil,
                sugars: nil,
                fiber: baseFiber > 0 ? baseFiber : nil
            )
            adjustedServings = result.servings
            #if DEBUG
            print("🧮 Base-serving mode: totals => base (÷\(divisor)) => carbs=\(baseCarbs), multiplier=\(adjustedServings)")
            #endif
        }
        
        // Include analysis notes in categories field for display
        let analysisInfo = result.analysisNotes ?? "AI food recognition analysis"
        
        return OpenFoodFactsProduct(
            id: aiId,
            productName: displayName.isEmpty ? "AI Analyzed Food" : displayName,
            brands: "AI Analysis",
            categories: analysisInfo,
            nutriments: adjustedNutriments,
            servingSize: servingSizeDisplay,
            servingQuantity: 100.0, // Use as base for per-serving calculations
            imageURL: nil,
            imageFrontURL: nil,
            code: nil,
            dataSource: .aiAnalysis
        )
    }
    
    /// Extract clean food name from AI analysis result for Food Type field
    private func extractFoodNameFromAIResult(_ result: AIFoodAnalysisResult) -> String {
        // Try to get the actual food name from the detailed analysis
        if let firstName = result.foodItemsDetailed.first?.name, !firstName.isEmpty {
            return cleanFoodNameForDisplay(firstName)
        }
        
        // Fallback to first food item from basic list
        if let firstFood = result.foodItems.first, !firstFood.isEmpty {
            return cleanFoodNameForDisplay(firstFood)
        }
        
        // If we have an overallDescription, try to extract a clean food name from it
        if let overallDesc = result.overallDescription, !overallDesc.isEmpty {
            return cleanFoodNameForDisplay(overallDesc)
        }
        
        // Last resort fallback
        return "AI Analyzed Food"
    }
    
    /// Clean up food name for display in Food Type field
    private func cleanFoodNameForDisplay(_ name: String) -> String {
        var cleaned = name
        
        // Remove measurement words and qualifiers that shouldn't be in food names
        let wordsToRemove = [
            "Approximately", "About", "Around", "Roughly", "Nearly",
            "ounces", "ounce", "oz", "grams", "gram", "g", "pounds", "pound", "lbs", "lb",
            "cups", "cup", "tablespoons", "tablespoon", "tbsp", "teaspoons", "teaspoon", "tsp",
            "slices", "slice", "pieces", "piece", "servings", "serving", "portions", "portion"
        ]
        
        // Remove these words with case-insensitive matching
        for word in wordsToRemove {
            let pattern = "\\b\(word)\\b"
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Remove numbers at the beginning (like "4 ounces of chicken" -> "chicken")
        cleaned = cleaned.replacingOccurrences(of: "^\\d+(\\.\\d+)?\\s*", with: "", options: .regularExpression)
        
        // Use centralized prefix cleaning from AIFoodAnalysis
        cleaned = ConfigurableAIService.cleanFoodText(cleaned) ?? cleaned
        
        // Clean up extra whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return cleaned.isEmpty ? "Mixed Food" : cleaned
    }
    
    /// Shortens food title to first 2-3 key words for less repetitive display
    private func shortenedTitle(_ fullTitle: String) -> String {
        let words = fullTitle.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        // If title is already short, return as-is
        if words.count <= 3 || fullTitle.count <= 25 {
            return fullTitle
        }
        
        // Extract first 2-3 meaningful words, avoiding articles and prepositions
        let meaningfulWords = words.prefix(4).filter { word in
            let lowercased = word.lowercased()
            return !["a", "an", "the", "with", "and", "or", "of", "in", "on", "at", "for", "to"].contains(lowercased)
        }
        
        // Take first 2-3 meaningful words
        let selectedWords = Array(meaningfulWords.prefix(3))
        
        if selectedWords.isEmpty {
            // Fallback to first 3 words if no meaningful words found
            return Array(words.prefix(3)).joined(separator: " ")
        }
        
        return selectedWords.joined(separator: " ")
    }
}

// MARK: - Warnings & Alerts
extension CarbEntryView {
    private var warningsCard: some View {
        Group {
            ForEach(Array(viewModel.warnings).sorted(by: { $0.priority < $1.priority })) { warning in
                warningView(for: warning)
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(CardBackground())
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
    }
    
    private func warningView(for warning: CarbEntryViewModel.Warning) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(triangleColor(for: warning))
            
            Text(warningText(for: warning))
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func triangleColor(for warning: CarbEntryViewModel.Warning) -> Color {
        switch warning {
        case .entryIsMissedMeal:
            return .critical
        case .overrideInProgress:
            return .warning
        }
    }
    
    private func warningText(for warning: CarbEntryViewModel.Warning) -> String {
        switch warning {
        case .entryIsMissedMeal:
            return NSLocalizedString("Loop has detected an missed meal and estimated its size. Edit the carb amount to match the amount of any carbs you may have eaten.", comment: "Warning displayed when user is adding a meal from an missed meal notification")
        case .overrideInProgress:
            return NSLocalizedString("An active override is modifying your carb ratio and insulin sensitivity. If you don't want this to affect your bolus calculation and projected glucose, consider turning off the override.", comment: "Warning to ensure the carb entry is accurate during an override")
        }
    }
    
    private func alert(for alert: CarbEntryViewModel.Alert) -> SwiftUI.Alert {
        switch alert {
        case .maxQuantityExceded:
            let message = String(
                format: NSLocalizedString("The maximum allowed amount is %@ grams.", comment: "Alert body displayed for quantity greater than max (1: maximum quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: viewModel.maxCarbEntryQuantity.doubleValue(for: viewModel.preferredCarbUnit)), number: .none)
            )
            let okMessage = NSLocalizedString("com.loudnate.LoopKit.errorAlertActionTitle", value: "OK", comment: "The title of the action used to dismiss an error alert")
            return SwiftUI.Alert(
                title: Text("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered"),
                message: Text(message),
                dismissButton: .cancel(Text(okMessage), action: viewModel.clearAlert)
            )
        case .warningQuantityValidation:
            let message = String(
                format: NSLocalizedString("Did you intend to enter %1$@ grams as the amount of carbohydrates for this meal?", comment: "Alert body when entered carbohydrates is greater than threshold (1: entered quantity in grams)"),
                NumberFormatter.localizedString(from: NSNumber(value: viewModel.carbsQuantity ?? 0), number: .none)
            )
            return SwiftUI.Alert(
                title: Text("Large Meal Entered", comment: "Title of the warning shown when a large meal was entered"),
                message: Text(message),
                primaryButton: .default(Text("No, edit amount", comment: "The title of the action used when rejecting the the amount of carbohydrates entered."), action: viewModel.clearAlert),
                secondaryButton: .cancel(Text("Yes", comment: "The title of the action used when confirming entered amount of carbohydrates."), action: viewModel.clearAlertAndContinueToBolus)
            )
        }
    }
}

// MARK: - Favorite Foods Card
extension CarbEntryView {
    private var favoriteFoodsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FAVORITE FOODS", comment: "The section title for Carb entry screen where Favorite Foods can be selected")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 26)
            
            VStack(spacing: 10) {
                if !viewModel.favoriteFoods.isEmpty {
                    VStack {
                        HStack {

                            Text("Choose Favorite:", comment: "The label for the row where you choose saved Favorite Food")
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 16, weight: .medium))
                            
                            let selectedFavorite = favoritedFoodTextFromIndex(viewModel.selectedFavoriteFoodIndex)
                            HStack(spacing: 8) {
                                Text(selectedFavorite)
                                    .minimumScaleFactor(0.8)
                                    .foregroundColor(viewModel.selectedFavoriteFoodIndex == -1 ? .blue : .primary)
                                if viewModel.selectedFavoriteFoodIndex >= 0 {
                                    let idx = viewModel.selectedFavoriteFoodIndex
                                    let foods = viewModel.favoriteFoods
                                    if idx < foods.count {
                                        if let thumb = thumbnailForFood(foods[idx]) {
                                            Image(uiImage: thumb)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 28, height: 28)
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                                                )
                                        } else {
                                            Text(foods[idx].foodType)
                                                .font(.system(size: 18))
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        
                        if expandedRow == .favoriteFoodSelection {
                            Picker(String(""), selection: $viewModel.selectedFavoriteFoodIndex) {
                                ForEach(-1..<viewModel.favoriteFoods.count, id: \.self) { index in
                                    HStack(spacing: 8) {
                                        Text(favoritedFoodTextFromIndex(index))
                                        if index >= 0 {
                                            let food = viewModel.favoriteFoods[index]
                                            if let thumb = thumbnailForFood(food) {
                                                Image(uiImage: thumb)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 28, height: 28)
                                                    .cornerRadius(6)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(Color(.systemGray4), lineWidth: 0.5)
                                                    )
                                            } else {
                                                Text(food.foodType)
                                                    .font(.system(size: 18))
                                            }
                                        }
                                    }
                                    .tag(index)
                                }
                            }
                            .pickerStyle(.wheel)
                            .onChange(of: viewModel.selectedFavoriteFoodIndex) { newValue in
                                viewModel.manualFavoriteFoodSelected(at: newValue)
                            }
                        }
                    }
                    .onTapGesture {
                        withAnimation {
                            if expandedRow == .favoriteFoodSelection {
                                expandedRow = nil
                            } else {
                                expandedRow = .favoriteFoodSelection
                            }
                        }
                    }
                    
                    CardSectionDivider()
                }
                
                Button(action: saveAsFavoriteFood) {
                    Text("Save as favorite food", comment: "Button label for saving current carb entry as a new Favorite Food")
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.saveFavoriteFoodButtonDisabled)
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .background(CardBackground())
            .padding(.horizontal)
        }
    }
    
    private func favoritedFoodTextFromIndex(_ index: Int) -> String {
        if index == -1 {
            return String(localized: "None", comment: "Indicates no favorite food is selected")
        }
        else {
            let food = viewModel.favoriteFoods[index]
            return food.name
        }
    }
    
    private func saveAsFavoriteFood() {
        self.showAddFavoriteFood = true
    }
    
    private func onFavoriteFoodSave(_ food: NewFavoriteFood) {
        clearExpandedRow()
        self.showAddFavoriteFood = false
        viewModel.onFavoriteFoodSave(food)
    }
}

extension CarbEntryView {
    private func thumbnailForFood(_ food: StoredFavoriteFood) -> UIImage? {
        let map = UserDefaults.standard.favoriteFoodImageIDs
        guard let id = map[food.id] else { return nil }
        return FavoriteFoodImageStore.loadThumbnail(id: id)
    }
}

// MARK: - Other UI Elements
extension CarbEntryView {
    // Quick favorite helpers
    private func isQuickFavorited(_ product: OpenFoodFactsProduct) -> Bool {
        let existing = viewModel.favoriteFoods
        // Consider a match by name + foodType when present
        let name = product.displayName
        return existing.contains { $0.name == name }
    }

    private func toggleQuickFavorite(for product: OpenFoodFactsProduct) {
        if isQuickFavorited(product) {
            // Already exists: do nothing for now (could navigate to favorites)
            return
        }
        // Build a NewFavoriteFood using current carbs, foodType, and absorption time
        let carbs = viewModel.carbsQuantity ?? 0
        guard carbs > 0 else { return }
        let new = NewFavoriteFood(
            name: product.displayName,
            carbsQuantity: HKQuantity(unit: viewModel.preferredCarbUnit, doubleValue: carbs),
            foodType: viewModel.foodType,
            absorptionTime: viewModel.absorptionTime
        )
        viewModel.onFavoriteFoodSave(new)
    }

    // Confidence helpers
    private func computeConfidencePercent(from ai: AIFoodAnalysisResult, servings: Double) -> Int {
        if let numeric = ai.numericConfidence {
            let pct = Int((min(1.0, max(0.0, numeric)) * 100).rounded())
            return max(20, min(97, pct))
        }
        // Start from provider-reported confidence band
        var percent: Int = {
            switch ai.confidence {
            case .high: return 88
            case .medium: return 68
            case .low: return 45
            }
        }()

        // Evidence-based small adjustments (keep within a narrow band to avoid 95% saturation)
        if ai.totalCarbohydrates > 0 { percent += 4 } else { percent -= 6 }
        if !ai.foodItemsDetailed.isEmpty { percent += 4 } else { percent -= 8 }
        if let method = ai.portionAssessmentMethod, !method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { percent += 3 }
        if let notes = ai.notes, notes.lowercased().contains("fallback") { percent -= 5 }

        // Penalize if multiple key fields are missing
        var missing = 0
        if ai.totalProtein == nil { missing += 1 }
        if ai.totalFat == nil { missing += 1 }
        if ai.totalCalories == nil { missing += 1 }
        if missing >= 2 { percent -= 6 }

        // Weird servings (very tiny or very large) slightly reduces confidence
        if servings < 0.3 || servings > 4.0 { percent -= 3 }

        // Clamp to sensible range and avoid clustering at 95
        percent = max(20, min(97, percent))
        return percent
    }
    
    private func confidenceColor(_ percent: Int) -> Color {
        if percent < 45 { return .red }
        if percent < 75 { return .yellow }
        return .green
    }

    private func confidenceBadgeColor(_ percent: Int) -> Color {
        if percent < 45 {
            return Color(.systemYellow).opacity(0.25)
        }
        if percent < 75 {
            return Color(.systemGray5)
        }
        return Color(.systemGray6)
    }
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Cancel", comment: "Button label for cancel")
        }
    }
    
    private var continueButton: some View {
        Button(action: viewModel.continueToBolus) {
            Text("Continue", comment: "Button label for continue")
        }
        .disabled(viewModel.continueButtonDisabled)
    }
    
    private var continueActionButton: some View {
        Button(action: viewModel.continueToBolus) {
            Text("Continue", comment: "Button label for continue")
        }
        .buttonStyle(ActionButtonStyle())
        .padding()
        .disabled(viewModel.continueButtonDisabled)
    }
    
    @ViewBuilder
    private func advancedAnalysisSection(aiResult: AIFoodAnalysisResult) -> some View {
        VStack(spacing: 0) {
            // Check if we have any advanced analysis content to show
            let hasAdvancedContent = hasAdvancedAnalysisContent(aiResult: aiResult)
            
            if hasAdvancedContent {
                // Expandable header for Advanced Analysis
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("Advanced Analysis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("(\(countAdvancedSections(aiResult: aiResult)) items)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: isAdvancedAnalysisExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(Color(.systemIndigo).opacity(0.08))
                .cornerRadius(12)
                
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isAdvancedAnalysisExpanded.toggle()
                    }
                }
                
                // Expandable content with all the advanced sections
                if isAdvancedAnalysisExpanded {
                    VStack(spacing: 12) {
                        // Fat/Protein Units (FPU) Analysis
                        if let fpuInfo = aiResult.fatProteinUnits, !fpuInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ExpandableNoteView(
                                icon: "chart.pie.fill",
                                iconColor: .orange,
                                title: "Fat/Protein Units (FPU):",
                                content: fpuInfo,
                                backgroundColor: Color(.systemOrange).opacity(0.08)
                            )
                        }
                        
                        // FPU Dosing Guidance
                        if let fpuDosing = aiResult.fpuDosingGuidance, !fpuDosing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ExpandableNoteView(
                                icon: "syringe.fill",
                                iconColor: .blue,
                                title: "Extended Dosing:",
                                content: fpuDosing,
                                backgroundColor: Color(.systemBlue).opacity(0.08)
                            )
                        }

                        // Net Carbs Adjustment (Fiber Impact)
                        if isUsefulAdvancedText(aiResult.netCarbsAdjustment) {
                            let netCarbs = aiResult.netCarbsAdjustment!.trimmingCharacters(in: .whitespacesAndNewlines)
                            ExpandableNoteView(
                                icon: "leaf.fill",
                                iconColor: .green,
                                title: "Fiber Impact (Net Carbs):",
                                content: netCarbs,
                                backgroundColor: Color(.systemGreen).opacity(0.08)
                            )
                        }
                        
                        // Insulin Timing Recommendations
                        if isUsefulAdvancedText(aiResult.insulinTimingRecommendations) {
                            let timingInfo = aiResult.insulinTimingRecommendations!.trimmingCharacters(in: .whitespacesAndNewlines)
                            ExpandableNoteView(
                                icon: "clock.fill",
                                iconColor: .purple,
                                title: "Insulin Timing:",
                                content: timingInfo,
                                backgroundColor: Color(.systemPurple).opacity(0.08)
                            )
                        }
                                                
                        // Exercise Considerations
                        if isUsefulAdvancedText(aiResult.exerciseConsiderations) {
                            let exerciseInfo = aiResult.exerciseConsiderations!.trimmingCharacters(in: .whitespacesAndNewlines)
                            ExpandableNoteView(
                                icon: "figure.run",
                                iconColor: .mint,
                                title: "Exercise Impact:",
                                content: exerciseInfo,
                                backgroundColor: Color(.systemMint).opacity(0.08)
                            )
                        }
                        
                        // Absorption Time Reasoning (when different from default)
                        if isUsefulAdvancedText(aiResult.absorptionTimeReasoning) {
                            let absorptionReasoning = aiResult.absorptionTimeReasoning!.trimmingCharacters(in: .whitespacesAndNewlines)
                            ExpandableNoteView(
                                icon: "hourglass.bottomhalf.fill",
                                iconColor: .indigo,
                                title: "Absorption Time Analysis:",
                                content: absorptionReasoning,
                                backgroundColor: Color(.systemIndigo).opacity(0.08)
                            )
                        }
                        
                        // Meal Size Impact
                        if isUsefulAdvancedText(aiResult.mealSizeImpact) {
                            let mealSizeInfo = aiResult.mealSizeImpact!.trimmingCharacters(in: .whitespacesAndNewlines)
                            ExpandableNoteView(
                                icon: "scalemass.fill",
                                iconColor: .brown,
                                title: "Meal Size Impact:",
                                content: mealSizeInfo,
                                backgroundColor: Color(.systemBrown).opacity(0.08)
                            )
                        }
                                                
                        // Safety Alerts (if different from main diabetes note)
                        if isUsefulAdvancedText(aiResult.safetyAlerts) {
                            let safetyInfo = aiResult.safetyAlerts!.trimmingCharacters(in: .whitespacesAndNewlines)
                            ExpandableNoteView(
                                icon: "exclamationmark.triangle.fill",
                                iconColor: .red,
                                title: "Safety Alerts:",
                                content: safetyInfo,
                                backgroundColor: Color(.systemRed).opacity(0.12)
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemIndigo).opacity(0.3), lineWidth: 1)
                    )
                    .padding(.top, 4)
                    
                    // Scope readout: make clear what's being shown
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        let servingText = viewModel.selectedFoodServingSize?.lowercased() ?? "serving"
                        if servingText.contains("medium") {
                            Text("Carbs shown for \(String(format: "%.2f", viewModel.numberOfServings)) × 1 medium item")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Carbs shown are for pictured portion")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    
                }
            }
        }
    }
    
    // Helper function to check if there's any advanced analysis content
    private func hasAdvancedAnalysisContent(aiResult: AIFoodAnalysisResult) -> Bool {
        return isUsefulAdvancedText(aiResult.fatProteinUnits) ||
               isUsefulAdvancedText(aiResult.netCarbsAdjustment) ||
               isUsefulAdvancedText(aiResult.insulinTimingRecommendations) ||
               isUsefulAdvancedText(aiResult.fpuDosingGuidance) ||
               isUsefulAdvancedText(aiResult.exerciseConsiderations) ||
               isUsefulAdvancedText(aiResult.absorptionTimeReasoning) ||
               isUsefulAdvancedText(aiResult.mealSizeImpact) ||
               isUsefulAdvancedText(aiResult.individualizationFactors) ||
               isUsefulAdvancedText(aiResult.safetyAlerts)
    }
    
    // Helper function to count advanced sections for display
    private func countAdvancedSections(aiResult: AIFoodAnalysisResult) -> Int {
        var count = 0
        if isUsefulAdvancedText(aiResult.fatProteinUnits) { count += 1 }
        if isUsefulAdvancedText(aiResult.netCarbsAdjustment) { count += 1 }
        if isUsefulAdvancedText(aiResult.insulinTimingRecommendations) { count += 1 }
        if isUsefulAdvancedText(aiResult.fpuDosingGuidance) { count += 1 }
        if isUsefulAdvancedText(aiResult.exerciseConsiderations) { count += 1 }
        if isUsefulAdvancedText(aiResult.absorptionTimeReasoning) { count += 1 }
        if isUsefulAdvancedText(aiResult.mealSizeImpact) { count += 1 }
        if isUsefulAdvancedText(aiResult.individualizationFactors) { count += 1 }
        if isUsefulAdvancedText(aiResult.safetyAlerts) { count += 1 }
        return count
    }

    // Treat placeholders like "none", "none needed", "n/a" as not useful
    private func isUsefulAdvancedText(_ text: String?) -> Bool {
        guard var s = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        if s.isEmpty { return false }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".! ")).lowercased()
        if s.isEmpty { return false }
        let junk: Set<String> = [
            "none", "none needed", "no", "n/a", "na", "not applicable",
            "no alerts", "no safety alerts", "no alert", "none required",
            "no change", "no changes", "no recommendation", "no recommendations"
        ]
        if junk.contains(s) { return false }
        // Filter very short generic words
        if s.count <= 3 { return false }
        return true
    }

private func fallbackPortionSummary(aiResult: AIFoodAnalysisResult) -> String {
        let items = aiResult.foodItemsDetailed
        guard !items.isEmpty else {
            return "Serving multipliers derived from the AI-estimated portions."
        }

        let snippets = items.prefix(3).map { item -> String in
            let name = cleanFoodNameForDisplay(item.name)
            let multiplier = item.servingMultiplier
            let multiplierText = multiplier > 0.01 ? String(format: "×%.2f", multiplier) : "unknown"
            if let usda = item.usdaServingSize?.trimmingCharacters(in: .whitespacesAndNewlines), !usda.isEmpty {
                return "\(name): \(multiplierText) vs \(usda)"
            }
            return "\(name): \(multiplierText) of USDA baseline"
        }

        var summary = "Serving multipliers derived from the AI-estimated portions."
        if !snippets.isEmpty {
            summary += " " + snippets.joined(separator: "; ")
            if items.count > snippets.count {
                summary += "…"
            }
        }
        return summary
    }

    @ViewBuilder
    private func detailedFoodBreakdownSection(aiResult: AIFoodAnalysisResult) -> some View {
        VStack(spacing: 0) {
            // Expandable header
            HStack {
                Image(systemName: "list.bullet.rectangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16, weight: .medium))
                
                Text("Food Details")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                let excludedCount = viewModel.excludedAIItemIndices.count
                let includedCount = max(0, aiResult.foodItemsDetailed.count - excludedCount)
                Text("(\(includedCount) of \(aiResult.foodItemsDetailed.count) items)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Image(systemName: expandedRow == .detailedFoodBreakdown ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(Color(.systemOrange).opacity(0.08))
            .cornerRadius(12)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    expandedRow = expandedRow == .detailedFoodBreakdown ? nil : .detailedFoodBreakdown
                }
            }
            
            // Expandable content
            if expandedRow == .detailedFoodBreakdown {
                VStack(spacing: 12) {
                    ForEach(Array(aiResult.foodItemsDetailed.enumerated()), id: \.offset) { index, foodItem in
                        // Card-style row with light gray boundary
                        VStack { renderAIItemRow(index: index, item: foodItem) }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemOrange).opacity(0.3), lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
    }

    // Small macro badge helper
    private func miniMacro(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(round(value)))")
                .font(.caption2)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(6)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Extracted row view to simplify ViewBuilder
    @ViewBuilder
    private func renderAIItemRow(index: Int, item: FoodItemAnalysis) -> some View {
        let isExcluded = viewModel.excludedAIItemIndices.contains(index)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(index + 1).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(item.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(isExcluded ? .secondary : .primary)
                    .strikethrough(isExcluded, color: .secondary)
                Spacer()
                // Carbs with subtle gray background for contrast
                Text("\(String(format: "%.1f", item.carbohydrates)) g carbs")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isExcluded ? .secondary : .blue)
                    .strikethrough(isExcluded, color: .secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button(action: {
                    if isExcluded { viewModel.excludedAIItemIndices.remove(index) }
                    else { viewModel.excludedAIItemIndices.insert(index) }
                    viewModel.recomputeAIAdjustments()
                }) {
                    Image(systemName: isExcluded ? "plus.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isExcluded ? .green : .red)
                        .font(.system(size: 18, weight: .medium))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                let trimmedUSDA = item.usdaServingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseMultiplier = item.servingMultiplier
                let usdaDisplay: String = {
                    if let text = trimmedUSDA, !text.isEmpty { return text }
                    if baseMultiplier > 0.01 {
                        return String(format: "Derived USDA portion (pictured is ×%.2f)", baseMultiplier)
                    }
                    return "Standard USDA portion"
                }()

                LinePair(label: "Normal USDA Serving:", value: usdaDisplay)
                LinePair(label: "Portion That I See:", value: item.portionEstimate.isEmpty ? "Unknown portion" : item.portionEstimate)

                if item.portionEstimate.uppercased().contains("CANNOT DETERMINE") {
                    Text("Estimated from menu text")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemYellow).opacity(0.3))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }

                if baseMultiplier > 0.01 && abs(baseMultiplier - 1.0) > 0.01 {
                    HStack(spacing: 6) {
                        Text("Difference:")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("×\(String(format: "%.2f", baseMultiplier)) for this item")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if viewModel.numberOfServings > 0,
                   let ai = viewModel.lastAIAnalysisResult,
                   ai.originalServings > 0 {
                    let mult = viewModel.numberOfServings / ai.originalServings
                    if abs(mult - 1.0) > 0.01 {
                        HStack(spacing: 6) {
                            Text("Adjusted Servings:")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Text("×\(String(format: "%.1f", mult)) applied to totals")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .foregroundColor(isExcluded ? .secondary : .primary)
            .opacity(isExcluded ? 0.7 : 1.0)
            
            HStack(spacing: 18) {
                VStack(spacing: 0) { Text("\(Int(round(item.calories ?? 0)))").foregroundColor(.green); Text("cal").font(.caption).foregroundColor(.secondary) }
                VStack(spacing: 0) { Text(String(format: "%.1f", item.fat ?? 0)).foregroundColor(Color.orange); Text("fat").font(.caption).foregroundColor(.secondary) }
                VStack(spacing: 0) { Text(String(format: "%.1f", item.fiber ?? 0)).foregroundColor(Color.purple); Text("fiber").font(.caption).foregroundColor(.secondary) }
                VStack(spacing: 0) { Text(String(format: "%.1f", item.protein ?? 0)).foregroundColor(.red); Text("protein").font(.caption).foregroundColor(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(isExcluded ? 0.25 : 1.0)
        }
    }

    // Compute displayed macro values for circles
    private func computeDisplayedMacros(selectedFood: OpenFoodFactsProduct, aiResult: AIFoodAnalysisResult?, numberOfServings: Double, excluded: Set<Int>) -> (carbs: Double, calories: Double?, fat: Double?, fiber: Double?, protein: Double?) {
        if let ai = aiResult {
            let servingScale = numberOfServings / ai.originalServings
            let included = ai.foodItemsDetailed.enumerated().filter { !excluded.contains($0.offset) }.map { $0.element }
            let carbs = included.reduce(0.0) { $0 + $1.carbohydrates } * servingScale
            let caloriesSum = included.compactMap { $0.calories }.reduce(0.0, +)
            let fatSum = included.compactMap { $0.fat }.reduce(0.0, +)
            let fiberSum = included.compactMap { $0.fiber }.reduce(0.0, +)
            let proteinSum = included.compactMap { $0.protein }.reduce(0.0, +)
            let cals: Double? = caloriesSum > 0 ? caloriesSum * servingScale : nil
            let fat: Double? = fatSum > 0 ? fatSum * servingScale : nil
            let fiber: Double? = fiberSum > 0 ? fiberSum * servingScale : nil
            let protein: Double? = proteinSum > 0 ? proteinSum * servingScale : nil
            return (carbs, cals, fat, fiber, protein)
        } else {
            let carbs = (selectedFood.carbsPerServing ?? selectedFood.nutriments.carbohydrates) * numberOfServings
            let cals = selectedFood.caloriesPerServing.map { $0 * numberOfServings }
            let fat = selectedFood.fatPerServing.map { $0 * numberOfServings }
            let fiber = selectedFood.fiberPerServing.map { $0 * numberOfServings }
            let protein = selectedFood.proteinPerServing.map { $0 * numberOfServings }
            return (carbs, cals, fat, fiber, protein)
        }
    }
}

private struct LinePair: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .layoutPriority(1)
                .lineLimit(1)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct BalancedMacroTargets {
    let carbs: Double
    let protein: Double
    let fat: Double
    let fiber: Double
    let calories: Double
}

private enum BalancedMealGuidelines {
    static let preferredCarbFraction: Double = 0.45
    static let preferredProteinFraction: Double = 0.20
    static let preferredFatFraction: Double = 0.30
    static let fiberPerCalorie: Double = 14.0 / 1000.0
}

private func computeBalancedTargets(carbs: Double, protein: Double?, fat: Double?, calories: Double?) -> BalancedMacroTargets? {
    let safeCarbs = max(carbs, 0)
    let safeProtein = max(protein ?? 0, 0)
    let safeFat = max(fat ?? 0, 0)
    let providedCalories = max(calories ?? 0, 0)

    let macrosCalories = safeCarbs * 4 + safeProtein * 4 + safeFat * 9
    let observedCalories = max(providedCalories, macrosCalories)

    let baselineCalories: Double
    if safeCarbs > 0 {
        let estimatedFromCarbs = (safeCarbs * 4) / BalancedMealGuidelines.preferredCarbFraction
        baselineCalories = max(observedCalories, estimatedFromCarbs)
    } else {
        baselineCalories = observedCalories
    }

    guard baselineCalories > 0 else {
        return nil
    }

    let targetCarbs = baselineCalories * BalancedMealGuidelines.preferredCarbFraction / 4
    let targetProtein = baselineCalories * BalancedMealGuidelines.preferredProteinFraction / 4
    let targetFat = baselineCalories * BalancedMealGuidelines.preferredFatFraction / 9
    let targetFiber = baselineCalories * BalancedMealGuidelines.fiberPerCalorie

    return BalancedMacroTargets(
        carbs: targetCarbs,
        protein: targetProtein,
        fat: targetFat,
        fiber: targetFiber,
        calories: baselineCalories
    )
}

// MARK: - ServingsRow Component

/// A row that always displays servings information
struct ServingsDisplayRow: View {
    @Binding var servings: Double
    let servingSize: String?
    let selectedFoodProduct: OpenFoodFactsProduct?
    
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        // Show quarters cleanly (e.g., 0.25, 0.5, 0.75, 1)
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()
    
    var body: some View {
        let hasSelectedFood = selectedFoodProduct != nil
        
        return HStack {
            Text("Servings")
                .foregroundColor(.primary)
            
            Spacer()
            
            if hasSelectedFood {
                // Show stepper controls when food is selected
                HStack(spacing: 8) {
                    // Decrease button
                    Button(action: {
                        // Step down by 0.25 (quarter serving)
                        let quarters = (servings * 4).rounded()
                        let newValue = max(0.0, (quarters - 1) / 4.0)
                        servings = newValue
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(servings > 0.0 ? .accentColor : .secondary)
                    }
                    .disabled(servings <= 0.0)
                    
                    // Current value
                    Text(formatter.string(from: NSNumber(value: servings)) ?? "1")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(minWidth: 30)
                    
                    // Increase button
                    Button(action: {
                        // Step up by 0.25 (quarter serving)
                        let quarters = (servings * 4).rounded()
                        let newValue = min(10.0, (quarters + 1) / 4.0)
                        servings = newValue
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(servings < 10.0 ? .accentColor : .secondary)
                    }
                    .disabled(servings >= 10.0)
                }
            } else {
                // Show placeholder when no food is selected
                Text("—")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 44)
        .padding(.vertical, -8)
    }
}

// MARK: - Nutrition Circle Component

/// Circular progress indicator for nutrition values with enhanced animations
struct NutritionCircle: View {
    let value: Double
    let unit: String
    let label: String
    let color: Color
    let maxValue: Double
    
    @State private var animatedValue: Double = 0
    @State private var animatedProgress: Double = 0
    @State private var isLoading: Bool = false
    
    private func normalizedProgress(for rawValue: Double) -> Double {
        guard maxValue > 0 else {
            return rawValue > 0 ? 1.0 : 0.0
        }
        let ratio = rawValue / maxValue
        if ratio.isNaN || ratio.isInfinite {
            return 0.0
        }
        return min(max(ratio, 0.0), 1.0)
    }
    
    private var displayValue: String {
        // Format animated value to 1 decimal place, but hide .0 for whole numbers
        if animatedValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", animatedValue)
        } else {
            return String(format: "%.1f", animatedValue)
        }
    }
    
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4.0)
                    .frame(width: 64, height: 64)
                
                if isLoading {
                    // Loading spinner
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(color)
                } else {
                    // Progress circle with smooth animation
                    Circle()
                        .trim(from: 0.0, to: animatedProgress)
                        .stroke(color, style: StrokeStyle(lineWidth: 4.0, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.8, dampingFraction: 0.8), value: animatedProgress)
                    
                    // Center text with count-up animation
                    HStack(spacing: 1) {
                        Text(displayValue)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .animation(.easeInOut(duration: 0.2), value: animatedValue)
                        Text(unit)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .offset(y: 1)
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) {
                    animatedValue = value
                    animatedProgress = normalizedProgress(for: value)
                }
            }
            .onChange(of: value) { newValue in
                if newValue == 0 && animatedValue > 0 {
                    isLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isLoading = false
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            animatedValue = newValue
                            animatedProgress = normalizedProgress(for: newValue)
                        }
                    }
                } else {
                    isLoading = false
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        animatedValue = newValue
                        animatedProgress = normalizedProgress(for: newValue)
                    }
                }
            }
            .onChange(of: maxValue) { _ in
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    animatedProgress = normalizedProgress(for: value)
                }
            }
            
            // Label
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Expandable Note Component

/// Expandable view for AI analysis notes that can be tapped to show full content
struct ExpandableNoteView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: String
    let backgroundColor: Color
    
    @State private var isExpanded = false
    @State private var headerWidth: CGFloat = 0
    
    // Estimate how many characters can fit in the single-line header area
    private var headerMaxChars: Int {
        // Available width is the measured header width minus fixed elements (icon, paddings, title, chevron reserve)
        let leftRightPadding: CGFloat = 24 // 12 + 12 from .padding(.horizontal, 12)
        let iconWidth: CGFloat = 16         // approximate SF Symbol at caption size
        let gaps: CGFloat = 12              // spacing between icon-title and title-content (6 + 6)
        let chevronReserve: CGFloat = 18    // space for chevron if needed
        
        // Measure title width using UIFont matching .caption
        let titleFont = UIFont.preferredFont(forTextStyle: .caption1)
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
        
        let available = max(0, headerWidth - leftRightPadding - iconWidth - gaps - titleWidth - chevronReserve)
        // Approximate average character width for .caption2
        let avgCharWidth: CGFloat = 6.0
        let maxChars = Int(floor(available / avgCharWidth))
        return max(0, maxChars)
    }

    // Collapsed single-line text snippet based on capacity
    private var collapsedLineText: String {
        let s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard headerMaxChars > 0 else { return "" }
        if s.count > headerMaxChars {
            let idx = s.index(s.startIndex, offsetBy: headerMaxChars)
            return String(s[..<idx]) + "…"
        }
        return s
    }

    // True only if there are characters beyond what the collapsed line can show
    private var isOverflowing: Bool {
        let sCount = content.trimmingCharacters(in: .whitespacesAndNewlines).count
        return sCount > headerMaxChars
    }
    
    private var borderColor: Color {
        // Extract border color from background color
        if backgroundColor == Color(.systemBlue).opacity(0.08) {
            return Color(.systemBlue).opacity(0.3)
        } else if backgroundColor == Color(.systemRed).opacity(0.08) {
            return Color(.systemRed).opacity(0.3)
        } else {
            return Color(.systemGray4)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Expandable header (always visible) - matches Food Details style
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Show truncated content when collapsed, or nothing when expanded
                if !isExpanded {
                    Text(collapsedLineText)
                        .font(.caption2)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                // Expansion indicator
                if isOverflowing {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .cornerRadius(12)
            .contentShape(Rectangle())
            // Measure header width to compute showable characters
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { headerWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { newValue in headerWidth = newValue }
                }
            )
            .onTapGesture {
                if isOverflowing {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }
            }
            
            // Expandable content (matches Food Details style)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(content)
                        .font(.caption2)
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Food Item Detail Row Component

/// Individual food item detail row for the breakdown section
struct FoodItemDetailRow: View {
    let foodItem: FoodItemAnalysis
    let itemNumber: Int
    let onDelete: (() -> Void)?
    
    init(foodItem: FoodItemAnalysis, itemNumber: Int, onDelete: (() -> Void)? = nil) {
        self.foodItem = foodItem
        self.itemNumber = itemNumber
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with food name and carbs
            HStack {
                // Item number
                Text("\(itemNumber).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20, alignment: .leading)
                
                // Food name
                Text(foodItem.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Spacer()
                
                // Carbs amount (highlighted)
                HStack(spacing: 4) {
                    Text("\(String(format: "%.1f", foodItem.carbohydrates))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text("g carbs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemBlue).opacity(0.1))
                .cornerRadius(8)
                
                // Delete button (if callback provided) - positioned after carbs
                if let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.leading, 8)
                }
            }
            
            // Portion details
            VStack(alignment: .leading, spacing: 6) {
                if !foodItem.portionEstimate.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What I see:")
                            .font(.caption)
                            .fontWeight(.light)
                            .foregroundColor(.secondary)
                        Text(foodItem.portionEstimate)
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                }
                
                if let usdaSize = foodItem.usdaServingSize, !usdaSize.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("USDA serving:")
                            .font(.caption)
                            .fontWeight(.light)
                            .foregroundColor(.secondary)
                        HStack {
                            Text(usdaSize)
                                .font(.caption)
                                .foregroundColor(.primary)
                            Text("(×\(String(format: "%.1f", foodItem.servingMultiplier)))")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24) // Align with food name
            
            // Additional nutrition if available
            let hasAnyNutrition = (foodItem.protein ?? 0) > 0 || (foodItem.fat ?? 0) > 0 || (foodItem.calories ?? 0) > 0 || (foodItem.fiber ?? 0) > 0
            
            if hasAnyNutrition {
                HStack(spacing: 12) {
                    Spacer()
                    
                    // Calories
                    if let calories = foodItem.calories, calories > 0 {
                        VStack(spacing: 2) {
                            Text("\(String(format: "%.0f", calories))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            Text("cal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Fat
                    if let fat = foodItem.fat, fat > 0 {
                        VStack(spacing: 2) {
                            Text("\(String(format: "%.1f", fat))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                            Text("fat")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Fiber (using purple color to match nutrition circles)
                    if let fiber = foodItem.fiber, fiber > 0 {
                        VStack(spacing: 2) {
                            Text("\(String(format: "%.1f", fiber))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                            Text("fiber")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Protein
                    if let protein = foodItem.protein, protein > 0 {
                        VStack(spacing: 2) {
                            Text("\(String(format: "%.1f", protein))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                            Text("protein")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - AI-enabled AbsorptionTimePickerRow
struct AIAbsorptionTimePickerRow: View {
    @Binding private var absorptionTime: TimeInterval
    @Binding private var isFocused: Bool
    
    private let validDurationRange: ClosedRange<TimeInterval>
    private let minuteStride: Int
    private let isAIGenerated: Bool
    private var showHowAbsorptionTimeWorks: Binding<Bool>?
    
    init(absorptionTime: Binding<TimeInterval>, isFocused: Binding<Bool>, validDurationRange: ClosedRange<TimeInterval>, minuteStride: Int = 30, isAIGenerated: Bool = false, showHowAbsorptionTimeWorks: Binding<Bool>? = nil) {
        self._absorptionTime = absorptionTime
        self._isFocused = isFocused
        self.validDurationRange = validDurationRange
        self.minuteStride = minuteStride
        self.isAIGenerated = isAIGenerated
        self.showHowAbsorptionTimeWorks = showHowAbsorptionTimeWorks
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Absorption Time")
                    .foregroundColor(.primary)
                
                if isAIGenerated {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.purple)
                        Text("AI")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
                
                if showHowAbsorptionTimeWorks != nil {
                    Button(action: {
                        isFocused = false
                        showHowAbsorptionTimeWorks?.wrappedValue = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundColor(.accentColor)
                    }
                }
                
                Spacer()
                
                Text(durationString())
                    .foregroundColor(isAIGenerated ? .blue : Color(UIColor.secondaryLabel))
                    .fontWeight(isAIGenerated ? .medium : .regular)
            }
            
            if isAIGenerated && !isFocused {
                Text("AI suggested based on meal composition")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.top, 2)
            }
            
            if isFocused {
                DurationPicker(duration: $absorptionTime, validDurationRange: validDurationRange, minuteInterval: minuteStride)
                    .frame(maxWidth: .infinity)
            }
        }
        .onTapGesture {
            withAnimation {
                isFocused.toggle()
            }
        }
    }
    
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter
    }()
    
    private func durationString() -> String {
        return durationFormatter.string(from: absorptionTime) ?? ""
    }
}

// MARK: - FoodFinder Enable Row
struct FoodSearchEnableRow: View {
    @Binding var isFoodSearchEnabled: Bool
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3)
                        .foregroundColor(.purple)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)
                    
                    Text("Enable FoodFinder")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isFoodSearchEnabled)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    .onChange(of: isFoodSearchEnabled) { newValue in
                        UserDefaults.standard.foodFinderEnabled = newValue
                    }
            }
            
            Text("Add AI-powered nutrition analysis")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
                .padding(.leading, 32) // Align with text above
        }
        .onAppear {
            isAnimating = true
        }
    }
}
