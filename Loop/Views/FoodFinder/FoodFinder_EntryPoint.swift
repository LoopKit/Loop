//
//  FoodFinder_EntryPoint.swift
//  Loop
//
//  FoodFinder — Single integration view encapsulating all FoodFinder UI.
//  CarbEntryView embeds this instead of inline FoodFinder code.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI
import HealthKit
import UIKit
import os.log

// MARK: - FoodFinder Entry Point

struct FoodFinder_EntryPoint: View {

    // MARK: - Host Bindings

    /// Carbs quantity in the host's CarbEntryViewModel
    @Binding var carbsQuantity: Double?

    /// Food type string in the host
    @Binding var foodType: String

    /// Absorption time in the host
    @Binding var absorptionTime: TimeInterval

    /// Whether the host's absorption time was manually edited
    var absorptionTimeWasEdited: Bool

    /// Default absorption times from CarbStore
    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes

    /// Optional callback when the user saves a favorite food
    var onFavoriteFoodSave: ((NewFavoriteFood) -> Void)?

    /// Optional binding so the host can observe the currently selected product
    var selectedFoodProduct: Binding<OpenFoodFactsProduct?>?

    /// Binding for the food name to pre-populate favorite food form
    @Binding var favoriteFoodName: String

    /// Binding for the captured AI image to use as favorite food thumbnail
    @Binding var favoriteFoodImage: UIImage?

    /// Optional binding for a restored AI analysis result from history selection.
    /// When set, the entry point consumes it (calling handleAIFoodAnalysis) and clears it.
    @Binding var restoredAnalysisResult: AIFoodAnalysisResult?

    /// Thumbnail ID from the selected history record, used to restore the product image.
    @Binding var restoredThumbnailID: String?

    /// Whether the current absorption time was set by AI analysis (exposed to host for row display).
    @Binding var absorptionTimeIsAIGenerated: Bool

    /// AI reasoning for the absorption time (exposed to host for inline display).
    @Binding var aiAbsorptionReasoning: String?

    // MARK: - Internal State

    @StateObject private var searchVM: FoodFinder_SearchViewModel

    @State private var showingAICamera = false
    @State private var showingAISettings = false
    @State private var showingFavoriteSheet = false
    @State private var isFoodSearchEnabled: Bool
    @State private var showAbsorptionReasoning = false
    @State private var isAdvancedAnalysisExpanded = false
    @State private var expandedRow: Row?

    /// Favorite foods loaded from UserDefaults for quick-favorite toggling.
    /// Kept lightweight — only names are needed for the heart-button check.
    @State private var favoriteFoods: [StoredFavoriteFood] = []

    enum Row: Hashable {
        case detailedFoodBreakdown, advancedAnalysis
    }

    // MARK: - Preferred Carb Unit (for favorite food save)

    private let preferredCarbUnit: HKUnit

    // MARK: - Init

    init(
        carbsQuantity: Binding<Double?>,
        foodType: Binding<String>,
        absorptionTime: Binding<TimeInterval>,
        absorptionTimeWasEdited: Bool,
        defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes,
        preferredCarbUnit: HKUnit = .gram(),
        onFavoriteFoodSave: ((NewFavoriteFood) -> Void)? = nil,
        selectedFoodProduct: Binding<OpenFoodFactsProduct?>? = nil,
        favoriteFoodName: Binding<String> = .constant(""),
        favoriteFoodImage: Binding<UIImage?> = .constant(nil),
        restoredAnalysisResult: Binding<AIFoodAnalysisResult?> = .constant(nil),
        restoredThumbnailID: Binding<String?> = .constant(nil),
        absorptionTimeIsAIGenerated: Binding<Bool> = .constant(false),
        aiAbsorptionReasoning: Binding<String?> = .constant(nil)
    ) {
        self._carbsQuantity = carbsQuantity
        self._foodType = foodType
        self._absorptionTime = absorptionTime
        self.absorptionTimeWasEdited = absorptionTimeWasEdited
        self.defaultAbsorptionTimes = defaultAbsorptionTimes
        self.preferredCarbUnit = preferredCarbUnit
        self.onFavoriteFoodSave = onFavoriteFoodSave
        self.selectedFoodProduct = selectedFoodProduct
        self._favoriteFoodName = favoriteFoodName
        self._favoriteFoodImage = favoriteFoodImage
        self._restoredAnalysisResult = restoredAnalysisResult
        self._restoredThumbnailID = restoredThumbnailID
        self._absorptionTimeIsAIGenerated = absorptionTimeIsAIGenerated
        self._aiAbsorptionReasoning = aiAbsorptionReasoning

        let initialEnabled = UserDefaults.standard.foodFinderEnabled
        self._isFoodSearchEnabled = State(initialValue: initialEnabled)

        self._searchVM = StateObject(wrappedValue: FoodFinder_SearchViewModel(
            defaultAbsorptionTimes: defaultAbsorptionTimes,
            initialAbsorptionTime: absorptionTime.wrappedValue
        ))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 10) {
            // Food search section (search bar, results, settings gear)
            if isFoodSearchEnabled {
                CardSectionDivider()

                foodSearchSection

                CardSectionDivider()

                ServingsDisplayRow(
                    servings: $searchVM.numberOfServings,
                    servingSize: searchVM.selectedFoodServingSize,
                    selectedFoodProduct: searchVM.selectedFoodProduct
                )
                .id("servings-\(searchVM.selectedFoodServingSize ?? "none")")
                .onChange(of: searchVM.numberOfServings) { newServings in
                    if let selectedFood = searchVM.selectedFoodProduct {
                        let expectedCarbs = (selectedFood.carbsPerServing ?? selectedFood.nutriments.carbohydrates) * newServings
                        if abs((carbsQuantity ?? 0) - expectedCarbs) > 0.01 {
                            carbsQuantity = expectedCarbs
                        }
                    }
                }

                // Product info card + nutrition circles + AI notes
                if let selectedFood = searchVM.selectedFoodProduct {
                    productInfoCard(selectedFood: selectedFood)
                    nutritionCirclesSection(selectedFood: selectedFood)

                    // AI analysis notes
                    if let aiResult = searchVM.lastAIAnalysisResult {
                        aiAnalysisNotesSection(aiResult: aiResult)
                    }
                }
            }

            // Food Search enable row (only when disabled)
            if !isFoodSearchEnabled {
                CardSectionDivider()

                FoodSearchEnableRow(isFoodSearchEnabled: $isFoodSearchEnabled)
                    .padding(.bottom, 2)
            }
        }
        .onAppear {
            FoodFinder_FeatureFlags.migrateToByoIfNeeded()
            isFoodSearchEnabled = UserDefaults.standard.foodFinderEnabled
            loadFavoriteFoods()
            wireSearchVMCallbacks()
            searchVM.setupObservers()
        }
        .onChange(of: restoredAnalysisResult) { newResult in
            guard let result = newResult else { return }
            // Restore thumbnail from history record
            if let thumbID = restoredThumbnailID,
               let thumbImage = FavoriteFoodImageStore.loadThumbnail(id: thumbID) {
                searchVM.capturedAIImage = thumbImage
                favoriteFoodImage = thumbImage
            }
            handleAIFoodAnalysis(result)
            // Clear after consuming so the next selection triggers a fresh change
            DispatchQueue.main.async {
                restoredAnalysisResult = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let currentSetting = UserDefaults.standard.foodFinderEnabled
            if currentSetting != isFoodSearchEnabled {
                isFoodSearchEnabled = currentSetting
            }
        }
        .sheet(isPresented: $showingAICamera) {
            AICameraView(
                onFoodAnalyzed: { result, capturedImage in
                    Task { @MainActor in
                        handleAIFoodAnalysis(result)
                        searchVM.capturedAIImage = capturedImage
                        favoriteFoodImage = capturedImage
                        showingAICamera = false
                        recordAnalysis(result, type: .image)
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
        .sheet(isPresented: $showingFavoriteSheet) {
            AddEditFavoriteFoodView(
                carbsQuantity: carbsQuantity,
                foodType: foodType,
                absorptionTime: absorptionTime,
                name: favoriteFoodName,
                thumbnailImage: searchVM.capturedAIImage,
                onSave: { food in
                    showingFavoriteSheet = false
                    onFavoriteFoodSave?(food)

                    // Save thumbnail linked to the newly created StoredFavoriteFood
                    if let image = searchVM.capturedAIImage,
                       let thumbId = FavoriteFoodImageStore.saveThumbnail(from: image) {
                        var imageMap = UserDefaults.standard.favoriteFoodImageIDs
                        imageMap[food.name] = thumbId
                        UserDefaults.standard.favoriteFoodImageIDs = imageMap
                    }

                    loadFavoriteFoods()
                }
            )
        }
    }

    // MARK: - Wire ViewModel Callbacks

    private func wireSearchVMCallbacks() {
        searchVM.onNutritionApplied = { result in
            carbsQuantity = result.carbs
            foodType = result.foodType
            absorptionTime = result.absorptionTime
            absorptionTimeIsAIGenerated = result.absorptionTimeWasAIGenerated
            aiAbsorptionReasoning = searchVM.lastAIAnalysisResult?.absorptionTimeReasoning
            // Mirror selected product to host if binding provided
            selectedFoodProduct?.wrappedValue = searchVM.selectedFoodProduct
        }
        searchVM.onFoodCleared = {
            selectedFoodProduct?.wrappedValue = nil
            absorptionTimeIsAIGenerated = false
            aiAbsorptionReasoning = nil
        }
        // When the search field detects natural language (e.g. iOS keyboard dictation),
        // the ViewModel routes through AI generative search and delivers the result here.
        searchVM.onGenerativeSearchResult = { result in
            handleAIFoodAnalysis(result)
            recordAnalysis(result, type: .dictation)
        }
    }

    // MARK: - Load Favorite Foods

    private func loadFavoriteFoods() {
        if let data = UserDefaults.standard.data(forKey: "com.loopkit.Loop.favoriteFoods"),
           let foods = try? JSONDecoder().decode([StoredFavoriteFood].self, from: data) {
            favoriteFoods = foods
        }
    }
}

// MARK: - Food Search Section

extension FoodFinder_EntryPoint {

    private var foodSearchSection: some View {
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
                searchText: $searchVM.foodSearchText,
                onBarcodeScanTapped: {
                    // Barcode scanning is handled by FoodSearchBar's sheet presentation
                },
                onAICameraTapped: {
                    showingAICamera = true
                },
                onDictationDetected: {
                    searchVM.lastInputWasDictated = true
                }
            )

            // Search results
            if searchVM.isFoodSearching || searchVM.showingFoodSearch || !searchVM.foodSearchResults.isEmpty {
                FoodSearchResultsView(
                    searchResults: searchVM.foodSearchResults,
                    isSearching: searchVM.isFoodSearching,
                    isAISearching: searchVM.isAISearching,
                    errorMessage: searchVM.foodSearchError,
                    onProductSelected: { product in
                        searchVM.selectFoodProduct(product)
                    }
                )
            }
        }
        .onAppear {
            searchVM.setupFoodSearchObservers()
        }
    }
}

// MARK: - Product Info Card

extension FoodFinder_EntryPoint {

    @ViewBuilder
    private func productInfoCard(selectedFood: OpenFoodFactsProduct) -> some View {
        VStack(spacing: 12) {
            // Product image at the top (works for both barcode and AI scanned images)
            if let capturedImage = searchVM.capturedAIImage {
                // Show AI captured image
                Image(uiImage: capturedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 90)
                    .clipped()
                    .cornerRadius(12)
            } else if let thumbnail = searchVM.productThumbnailImage {
                // Show pre-downloaded product thumbnail (avoids AsyncImage rebuild issues)
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 90)
                    .clipped()
                    .cornerRadius(12)
            } else if (selectedFood.imageThumbURL ?? selectedFood.imageFrontSmallURL ?? selectedFood.imageFrontURL ?? selectedFood.imageURL) != nil {
                // Static placeholder while thumbnail downloads (OFF images can be slow)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: 120, height: 90)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.system(size: 28))
                            .foregroundColor(Color(.systemGray3))
                    )
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
                    Button(action: {
                        if !isQuickFavorited(selectedFood) {
                            showingFavoriteSheet = true
                        }
                    }) {
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

            // Serving size — replace "CANNOT DETERMINE" with the actual USDA standard serving size
            if selectedFood.servingSizeDisplay.uppercased().contains("CANNOT DETERMINE") {
                let usdaSize = searchVM.lastAIAnalysisResult?.foodItemsDetailed.first?.usdaServingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let usda = usdaSize, !usda.isEmpty {
                    Text("USDA standard serving: \(usda). Adjust servings as needed.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    let foodName = shortenedTitle(selectedFood.displayName)
                    Text("Based on a standard serving of \(foodName). Adjust servings as needed.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if selectedFood.dataSource == .barcodeScan {
                Text("Package Serving Size: \(selectedFood.servingSizeDisplay)")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            } else {
                Text(selectedFood.servingSizeDisplay)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.top, 8)
    }
}

// MARK: - Nutrition Circles Section

extension FoodFinder_EntryPoint {

    @ViewBuilder
    private func nutritionCirclesSection(selectedFood: OpenFoodFactsProduct) -> some View {
        VStack(spacing: 8) {
            // Horizontal scrollable nutrition indicators
            HStack(alignment: .center) {
                Spacer()
                HStack(alignment: .center, spacing: 12) {
                    let aiResult = searchVM.lastAIAnalysisResult

                    let valuesTuple = computeDisplayedMacros(
                        selectedFood: selectedFood,
                        aiResult: aiResult,
                        numberOfServings: searchVM.numberOfServings,
                        excluded: searchVM.excludedAIItemIndices
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
                        color: Color(red: 0.4, green: 0.7, blue: 1.0),
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
                            color: Color(red: 0.5, green: 0.8, blue: 0.4),
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
                            color: Color(red: 1.0, green: 0.8, blue: 0.2),
                            maxValue: max(fatTarget, 1)
                        )
                    } else if let fat = fatValue, fat > 0 {
                        NutritionCircle(
                            value: fat,
                            unit: "g",
                            label: "Fat",
                            color: Color(red: 1.0, green: 0.8, blue: 0.2),
                            maxValue: 20.0
                        )
                    }

                    // Fiber (fourth)
                    if let fiberTarget = balancedTargets?.fiber, fiberTarget > 0 {
                        let fiberAmount = max(fiberValue ?? 0, 0)
                        NutritionCircle(
                            value: fiberAmount,
                            unit: "g",
                            label: "Fiber",
                            color: Color(red: 0.6, green: 0.4, blue: 0.8),
                            maxValue: max(fiberTarget, 1)
                        )
                    } else if let fiber = fiberValue, fiber > 0 {
                        NutritionCircle(
                            value: fiber,
                            unit: "g",
                            label: "Fiber",
                            color: Color(red: 0.6, green: 0.4, blue: 0.8),
                            maxValue: 10.0
                        )
                    }

                    // Protein (fifth)
                    if let proteinTarget = balancedTargets?.protein, proteinTarget > 0 {
                        let proteinAmount = max(proteinValue ?? 0, 0)
                        NutritionCircle(
                            value: proteinAmount,
                            unit: "g",
                            label: "Protein",
                            color: Color(red: 1.0, green: 0.4, blue: 0.4),
                            maxValue: max(proteinTarget, 1)
                        )
                    } else if let protein = proteinValue, protein > 0 {
                        NutritionCircle(
                            value: protein,
                            unit: "g",
                            label: "Protein",
                            color: Color(red: 1.0, green: 0.4, blue: 0.4),
                            maxValue: 30.0
                        )
                    }
                }
                Spacer()
            }
            .frame(height: 90)
            .id("nutrition-circles-\(searchVM.numberOfServings)")

            // Confidence line (AI only)
            Group {
                if let ai = searchVM.lastAIAnalysisResult {
                    let pct = computeConfidencePercent(from: ai, servings: searchVM.numberOfServings)
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
        .padding(.top, 8)
    }
}

// MARK: - AI Analysis Notes Section

extension FoodFinder_EntryPoint {

    @ViewBuilder
    private func aiAnalysisNotesSection(aiResult: AIFoodAnalysisResult) -> some View {
        VStack(spacing: 8) {
            // Detailed Food Breakdown (expandable)
            if !aiResult.foodItemsDetailed.isEmpty {
                detailedFoodBreakdownSection(aiResult: aiResult)
            }

            // Portion estimation method (expandable)
            let trimmedPortion = aiResult.portionAssessmentMethod?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let portionSummary = trimmedPortion.isEmpty ? fallbackPortionSummary(aiResult: aiResult) : trimmedPortion
            if !portionSummary.isEmpty {
                let pct = computeConfidencePercent(from: aiResult, servings: searchVM.numberOfServings)
                let confidenceLine = pct < 60 ? "Confidence: \(pct)% -- treat as estimate" : "Confidence: \(pct)%"
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
            if UserDefaults.standard.foodFinder_advancedDosingRecommendationsEnabled {
                advancedAnalysisSection(aiResult: aiResult)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

// MARK: - Detailed Food Breakdown

extension FoodFinder_EntryPoint {

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

                let excludedCount = searchVM.excludedAIItemIndices.count
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

    @ViewBuilder
    private func renderAIItemRow(index: Int, item: FoodItemAnalysis) -> some View {
        let isExcluded = searchVM.excludedAIItemIndices.contains(index)
        VStack(alignment: .leading, spacing: 10) {
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
                    if isExcluded { searchVM.excludedAIItemIndices.remove(index) }
                    else { searchVM.excludedAIItemIndices.insert(index) }
                    searchVM.recomputeAIAdjustments()
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
                        return String(format: "Derived USDA portion (pictured is x%.2f)", baseMultiplier)
                    }
                    return "Standard USDA portion"
                }()

                FoodFinder_LinePair(label: "Normal USDA Serving:", value: usdaDisplay)

                if item.portionEstimate.uppercased().contains("CANNOT DETERMINE") {
                    FoodFinder_LinePair(label: "Portion:", value: "No photo — using standard USDA serving for \(item.name)")
                    Text("Values based on standard portion")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemBlue).opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                } else {
                    FoodFinder_LinePair(label: "Portion That I See:", value: item.portionEstimate.isEmpty ? "Unknown portion" : item.portionEstimate)
                }

                if baseMultiplier > 0.01 && abs(baseMultiplier - 1.0) > 0.01 {
                    HStack(spacing: 6) {
                        Text("Difference:")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Text("x\(String(format: "%.2f", baseMultiplier)) for this item")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if searchVM.numberOfServings > 0,
                   let ai = searchVM.lastAIAnalysisResult,
                   ai.originalServings > 0 {
                    let mult = searchVM.numberOfServings / ai.originalServings
                    if abs(mult - 1.0) > 0.01 {
                        HStack(spacing: 6) {
                            Text("Adjusted Servings:")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Text("x\(String(format: "%.1f", mult)) applied to totals")
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
}

// MARK: - Advanced Analysis Section

extension FoodFinder_EntryPoint {

    @ViewBuilder
    private func advancedAnalysisSection(aiResult: AIFoodAnalysisResult) -> some View {
        VStack(spacing: 0) {
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

                    // Scope readout
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        let servingText = searchVM.selectedFoodServingSize?.lowercased() ?? "serving"
                        if servingText.contains("medium") {
                            Text("Carbs shown for \(String(format: "%.2f", searchVM.numberOfServings)) x 1 medium item")
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
        if s.count <= 3 { return false }
        return true
    }
}

// MARK: - AI Food Analysis Handler

extension FoodFinder_EntryPoint {

    /// Handle AI food analysis results by converting to food product format
    @MainActor
    private func handleAIFoodAnalysis(_ result: AIFoodAnalysisResult) {
        var enrichedResult = result
        searchVM.ensureAbsorptionTimeForInitialResult(&enrichedResult)
        showAbsorptionReasoning = false

        // Store the detailed AI result for UI display
        searchVM.lastAIAnalysisResult = enrichedResult

        // Convert AI result to OpenFoodFactsProduct format for consistency
        let aiProduct = convertAIResultToFoodProduct(enrichedResult)

        // Update favorite food name binding for pre-populating the favorite food form
        favoriteFoodName = extractFoodNameFromAIResult(enrichedResult)

        // Use existing food selection workflow
        searchVM.selectFoodProduct(aiProduct)

        // Calculate final servings value once to avoid multiple onChange triggers per frame
        var finalServings: Double = 1.0
        if enrichedResult.servings > 0 && enrichedResult.servings < 0.95 {
            if enrichedResult.servingSizeDescription.localizedCaseInsensitiveContains("medium") {
                finalServings = enrichedResult.servings
            }
        } else if enrichedResult.servings >= 0.95 {
            finalServings = enrichedResult.servings
        }

        // Soft clamp for obvious slice-based overestimates
        if enrichedResult.servingSizeDescription.localizedCaseInsensitiveContains("medium") {
            let portionText = (enrichedResult.analysisNotes ?? enrichedResult.servingSizeDescription).lowercased()
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
                    if cap > 0 && finalServings > cap {
                        #if DEBUG
                        print("Applying slice-based soft cap: AI=\(finalServings) -> cap=\(cap) for \(count) slice(s)")
                        #endif
                        finalServings = cap
                    }
                }
            }
        }

        // Single assignment — avoids multiple onChange triggers per frame
        searchVM.numberOfServings = finalServings

        // Set dynamic absorption time from AI analysis
        if let absorptionHours = enrichedResult.absorptionTimeHours,
           absorptionHours > 0 {
            let absorptionTimeInterval = TimeInterval(absorptionHours * 3600)

            searchVM.absorptionEditIsProgrammatic = true
            absorptionTime = absorptionTimeInterval
            searchVM.absorptionTime = absorptionTimeInterval

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchVM.absorptionTimeWasAIGenerated = true
            }
        }

    }

    /// Record an AI analysis to the history store for future re-entry.
    /// Also posts a notification so future features (e.g. LoopInsights) can
    /// observe meal events in real-time without importing FoodFinder code.
    private func recordAnalysis(_ result: AIFoodAnalysisResult, type: FoodFinder_AnalysisRecord.AnalysisType) {
        let name = extractFoodNameFromAIResult(result)
        let aiCarbs = result.carbohydrates
        let absTime = result.absorptionTimeHours.map { TimeInterval($0 * 3600) }
            ?? absorptionTime

        var thumbID: String? = nil
        if type == .image, let img = searchVM.capturedAIImage {
            thumbID = FavoriteFoodImageStore.saveThumbnail(from: img)
        }

        // Capture AI confidence for LoopInsights correlation analysis
        let confidence: Int? = {
            guard let ai = searchVM.lastAIAnalysisResult else { return nil }
            if let numeric = ai.numericConfidence {
                return max(20, min(97, Int((min(1.0, max(0.0, numeric)) * 100).rounded())))
            }
            switch ai.confidence {
            case .high: return 88
            case .medium: return 68
            case .low: return 45
            }
        }()

        let record = FoodFinder_AnalysisRecord(
            id: UUID().uuidString,
            name: name,
            carbsGrams: aiCarbs,
            foodType: foodType,
            absorptionTime: absTime,
            analysisType: type,
            date: Date(),
            thumbnailID: thumbID,
            analysisResult: result,
            originalAICarbs: aiCarbs,
            aiConfidencePercent: confidence
        )
        FoodFinder_AnalysisHistoryStore.record(record)

        // Broadcast for LoopInsights or any future observer.
        // userInfo contains the record ID so listeners can look it up.
        NotificationCenter.default.post(
            name: .foodFinderMealLogged,
            object: nil,
            userInfo: ["recordID": record.id]
        )
    }

    /// Convert AI analysis result to OpenFoodFactsProduct for integration with existing workflow
    private func convertAIResultToFoodProduct(_ result: AIFoodAnalysisResult) -> OpenFoodFactsProduct {
        let aiId = "ai_\(UUID().uuidString.prefix(8))"
        let displayName = extractFoodNameFromAIResult(result)

        let aiServings = result.servings
        let useTotalsAsServing = aiServings > 0 && aiServings < 0.95
        #if DEBUG
        print("AI scaling: servings=\(aiServings), useTotalsAsServing=\(useTotalsAsServing)")
        #endif
        let baseDivisor = useTotalsAsServing ? 1.0 : max(1.0, aiServings)
        let carbsPerServing = result.carbohydrates / baseDivisor
        let proteinPerServing = (result.protein ?? 0) / baseDivisor
        let fatPerServing = (result.fat ?? 0) / baseDivisor
        let caloriesPerServing = (result.calories ?? 0) / baseDivisor
        let fiberPerServing = (result.fiber ?? 0) / baseDivisor

        let nutriments = Nutriments(
            carbohydrates: carbsPerServing,
            proteins: proteinPerServing > 0 ? proteinPerServing : nil,
            fat: fatPerServing > 0 ? fatPerServing : nil,
            calories: caloriesPerServing > 0 ? caloriesPerServing : nil,
            sugars: nil,
            fiber: fiberPerServing > 0 ? fiberPerServing : nil
        )

        let servingSizeDisplay = result.servingSizeDescription

        var adjustedNutriments = nutriments
        var adjustedServings = result.servings
        if result.servings > 0, result.servings < 0.95, servingSizeDisplay.localizedCaseInsensitiveContains("medium") {
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
            print("Base-serving mode: totals => base (div \(divisor)) => carbs=\(baseCarbs), multiplier=\(adjustedServings)")
            #endif
        }

        let analysisInfo = result.analysisNotes ?? "AI food recognition analysis"

        return OpenFoodFactsProduct(
            id: aiId,
            productName: displayName.isEmpty ? "AI Analyzed Food" : displayName,
            brands: "AI Analysis",
            categories: analysisInfo,
            nutriments: adjustedNutriments,
            servingSize: servingSizeDisplay,
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontURL: nil,
            code: nil,
            dataSource: .aiAnalysis
        )
    }

    /// Extract clean food name from AI analysis result for Food Type field
    private func extractFoodNameFromAIResult(_ result: AIFoodAnalysisResult) -> String {
        if let firstName = result.foodItemsDetailed.first?.name, !firstName.isEmpty {
            return cleanFoodNameForDisplay(firstName)
        }
        if let firstFood = result.foodItems.first, !firstFood.isEmpty {
            return cleanFoodNameForDisplay(firstFood)
        }
        if let overallDesc = result.overallDescription, !overallDesc.isEmpty {
            return cleanFoodNameForDisplay(overallDesc)
        }
        return "AI Analyzed Food"
    }

    /// Clean up food name for display in Food Type field
    private func cleanFoodNameForDisplay(_ name: String) -> String {
        var cleaned = name

        let wordsToRemove = [
            "Approximately", "About", "Around", "Roughly", "Nearly",
            "ounces", "ounce", "oz", "grams", "gram", "g", "pounds", "pound", "lbs", "lb",
            "cups", "cup", "tablespoons", "tablespoon", "tbsp", "teaspoons", "teaspoon", "tsp",
            "slices", "slice", "pieces", "piece", "servings", "serving", "portions", "portion"
        ]

        for word in wordsToRemove {
            let pattern = "\\b\(word)\\b"
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        cleaned = cleaned.replacingOccurrences(of: "^\\d+(\\.\\d+)?\\s*", with: "", options: .regularExpression)

        cleaned = ConfigurableAIService.cleanFoodText(cleaned) ?? cleaned

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return cleaned.isEmpty ? "Mixed Food" : cleaned
    }
}

// MARK: - Helper Functions

extension FoodFinder_EntryPoint {

    /// Shortens food title to first 2-3 key words for less repetitive display
    private func shortenedTitle(_ fullTitle: String) -> String {
        let words = fullTitle.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        if words.count <= 3 || fullTitle.count <= 25 {
            return fullTitle
        }

        let meaningfulWords = words.prefix(4).filter { word in
            let lowercased = word.lowercased()
            return !["a", "an", "the", "with", "and", "or", "of", "in", "on", "at", "for", "to"].contains(lowercased)
        }

        let selectedWords = Array(meaningfulWords.prefix(3))

        if selectedWords.isEmpty {
            return Array(words.prefix(3)).joined(separator: " ")
        }

        return selectedWords.joined(separator: " ")
    }

    // Quick favorite helpers
    private func isQuickFavorited(_ product: OpenFoodFactsProduct) -> Bool {
        let name = product.displayName
        return favoriteFoods.contains { $0.name == name }
    }

    private func toggleQuickFavorite(for product: OpenFoodFactsProduct) {
        if isQuickFavorited(product) {
            return
        }
        let carbs = carbsQuantity ?? 0
        guard carbs > 0 else { return }
        let new = NewFavoriteFood(
            name: product.displayName,
            carbsQuantity: HKQuantity(unit: preferredCarbUnit, doubleValue: carbs),
            foodType: foodType,
            absorptionTime: absorptionTime
        )
        onFavoriteFoodSave?(new)
        // Reload favorites so heart fills immediately
        loadFavoriteFoods()
    }

    // Confidence helpers
    private func computeConfidencePercent(from ai: AIFoodAnalysisResult, servings: Double) -> Int {
        if let numeric = ai.numericConfidence {
            let pct = Int((min(1.0, max(0.0, numeric)) * 100).rounded())
            return max(20, min(97, pct))
        }
        var percent: Int = {
            switch ai.confidence {
            case .high: return 88
            case .medium: return 68
            case .low: return 45
            }
        }()

        if ai.totalCarbohydrates > 0 { percent += 4 } else { percent -= 6 }
        if !ai.foodItemsDetailed.isEmpty { percent += 4 } else { percent -= 8 }
        if let method = ai.portionAssessmentMethod, !method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { percent += 3 }
        if let notes = ai.notes, notes.lowercased().contains("fallback") { percent -= 5 }

        var missing = 0
        if ai.totalProtein == nil { missing += 1 }
        if ai.totalFat == nil { missing += 1 }
        if ai.totalCalories == nil { missing += 1 }
        if missing >= 2 { percent -= 6 }

        if servings < 0.3 || servings > 4.0 { percent -= 3 }

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

    private func fallbackPortionSummary(aiResult: AIFoodAnalysisResult) -> String {
        let items = aiResult.foodItemsDetailed
        guard !items.isEmpty else {
            return "Serving multipliers derived from the AI-estimated portions."
        }

        let snippets = items.prefix(3).map { item -> String in
            let name = cleanFoodNameForDisplay(item.name)
            let multiplier = item.servingMultiplier
            let multiplierText = multiplier > 0.01 ? String(format: "x%.2f", multiplier) : "unknown"
            if let usda = item.usdaServingSize?.trimmingCharacters(in: .whitespacesAndNewlines), !usda.isEmpty {
                return "\(name): \(multiplierText) vs \(usda)"
            }
            return "\(name): \(multiplierText) of USDA baseline"
        }

        var summary = "Serving multipliers derived from the AI-estimated portions."
        if !snippets.isEmpty {
            summary += " " + snippets.joined(separator: "; ")
            if items.count > snippets.count {
                summary += "..."
            }
        }
        return summary
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

// MARK: - Balanced Macro Targets (private to this file)

private struct FoodFinder_BalancedMacroTargets {
    let carbs: Double
    let protein: Double
    let fat: Double
    let fiber: Double
    let calories: Double
}

private enum FoodFinder_BalancedMealGuidelines {
    static let preferredCarbFraction: Double = 0.45
    static let preferredProteinFraction: Double = 0.20
    static let preferredFatFraction: Double = 0.30
    static let fiberPerCalorie: Double = 14.0 / 1000.0
}

private func computeBalancedTargets(carbs: Double, protein: Double?, fat: Double?, calories: Double?) -> FoodFinder_BalancedMacroTargets? {
    let safeCarbs = max(carbs, 0)
    let safeProtein = max(protein ?? 0, 0)
    let safeFat = max(fat ?? 0, 0)
    let providedCalories = max(calories ?? 0, 0)

    let macrosCalories = safeCarbs * 4 + safeProtein * 4 + safeFat * 9
    let observedCalories = max(providedCalories, macrosCalories)

    let baselineCalories: Double
    if safeCarbs > 0 {
        let estimatedFromCarbs = (safeCarbs * 4) / FoodFinder_BalancedMealGuidelines.preferredCarbFraction
        baselineCalories = max(observedCalories, estimatedFromCarbs)
    } else {
        baselineCalories = observedCalories
    }

    guard baselineCalories > 0 else {
        return nil
    }

    let targetCarbs = baselineCalories * FoodFinder_BalancedMealGuidelines.preferredCarbFraction / 4
    let targetProtein = baselineCalories * FoodFinder_BalancedMealGuidelines.preferredProteinFraction / 4
    let targetFat = baselineCalories * FoodFinder_BalancedMealGuidelines.preferredFatFraction / 9
    let targetFiber = baselineCalories * FoodFinder_BalancedMealGuidelines.fiberPerCalorie

    return FoodFinder_BalancedMacroTargets(
        carbs: targetCarbs,
        protein: targetProtein,
        fat: targetFat,
        fiber: targetFiber,
        calories: baselineCalories
    )
}

// MARK: - FoodFinder_LinePair (private to this file)

private struct FoodFinder_LinePair: View {
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
                Text("\u{2014}")
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
        let leftRightPadding: CGFloat = 24
        let iconWidth: CGFloat = 16
        let gaps: CGFloat = 12
        let chevronReserve: CGFloat = 18

        let titleFont = UIFont.preferredFont(forTextStyle: .caption1)
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width

        let available = max(0, headerWidth - leftRightPadding - iconWidth - gaps - titleWidth - chevronReserve)
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
            return String(s[..<idx]) + "..."
        }
        return s
    }

    // True only if there are characters beyond what the collapsed line can show
    private var isOverflowing: Bool {
        let sCount = content.trimmingCharacters(in: .whitespacesAndNewlines).count
        return sCount > headerMaxChars
    }

    private var borderColor: Color {
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
            // Expandable header (always visible)
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

            // Expandable content
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

                // Delete button (if callback provided)
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
                            Text("(x\(String(format: "%.1f", foodItem.servingMultiplier)))")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)

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

                    // Fiber
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
                .padding(.leading, 32)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - AI-enabled AbsorptionTimePickerRow

struct AIAbsorptionTimePickerRow: View {
    @Binding private var absorptionTime: TimeInterval
    @Binding private var isFocused: Bool

    private let validDurationRange: ClosedRange<TimeInterval>
    private let minuteStride: Int
    private let isAIGenerated: Bool
    private let absorptionReasoning: String?
    private var showHowAbsorptionTimeWorks: Binding<Bool>?

    @State private var showReasoning = false

    init(absorptionTime: Binding<TimeInterval>, isFocused: Binding<Bool>, validDurationRange: ClosedRange<TimeInterval>, minuteStride: Int = 30, isAIGenerated: Bool = false, absorptionReasoning: String? = nil, showHowAbsorptionTimeWorks: Binding<Bool>? = nil) {
        self._absorptionTime = absorptionTime
        self._isFocused = isFocused
        self.validDurationRange = validDurationRange
        self.minuteStride = minuteStride
        self.isAIGenerated = isAIGenerated
        self.absorptionReasoning = absorptionReasoning
        self.showHowAbsorptionTimeWorks = showHowAbsorptionTimeWorks
    }

    /// True when AI set a non-default absorption time (not 3 hours) and reasoning exists.
    private var hasNonDefaultReasoning: Bool {
        guard isAIGenerated,
              let reasoning = absorptionReasoning?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reasoning.isEmpty else { return false }
        let hours = absorptionTime / 3600
        return abs(hours - 3.0) > 0.01
    }

    private var hoursLabel: String {
        let hours = absorptionTime / 3600
        if hours == hours.rounded() {
            return String(format: "%.0f", hours)
        }
        return String(format: "%.1f", hours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Absorption Time")
                    .foregroundColor(.primary)
                    .layoutPriority(1)

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

                if hasNonDefaultReasoning {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showReasoning.toggle()
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text("Why \(hoursLabel) hrs?")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.center)
                            Image(systemName: showReasoning ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.purple)
                        .frame(width: 100)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(durationString())
                    .foregroundColor(isAIGenerated ? .blue : Color(UIColor.secondaryLabel))
                    .fontWeight(isAIGenerated ? .medium : .regular)
                    .layoutPriority(1)
            }

            if showReasoning, let reasoning = absorptionReasoning {
                Text(reasoning)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
