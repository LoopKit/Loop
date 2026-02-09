//
//  FoodFinder_SearchViewModel.swift
//  Loop
//
//  Extracted from CarbEntryViewModel.swift — all FoodFinder food-search
//  state and logic now lives in this self-contained ViewModel.
//
//  Created by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit
import Combine
import os.log
import ObjectiveC
import UIKit

// MARK: - Timeout Utilities

/// Error thrown when an operation times out
struct FoodFinder_TimeoutError: Error {
    let duration: TimeInterval

    var localizedDescription: String {
        return "Operation timed out after \(duration) seconds"
    }
}

/// Execute an async operation with a timeout
/// - Parameters:
///   - seconds: Timeout duration in seconds
///   - operation: The async operation to execute
/// - Throws: FoodFinder_TimeoutError if the operation doesn't complete within the timeout
func foodFinder_withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation
        group.addTask {
            try await operation()
        }

        // Add the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw FoodFinder_TimeoutError(duration: seconds)
        }

        // Return the first result and cancel the other task
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Nutrition Result Tuple

/// The payload delivered to the host (CarbEntryView / CarbEntryViewModel)
/// when the user confirms a food selection or AI analysis.
struct FoodFinder_NutritionResult {
    let carbs: Double
    let foodType: String
    let absorptionTime: TimeInterval
    let absorptionTimeWasAIGenerated: Bool
}

// MARK: - Search ViewModel

final class FoodFinder_SearchViewModel: ObservableObject {

    // MARK: - Callback to Host

    /// The host sets this closure so it can receive nutrition updates
    /// when the user selects a food product or AI analysis completes.
    var onNutritionApplied: ((FoodFinder_NutritionResult) -> Void)?

    /// Callback when the selected food is cleared so the host can reset its fields.
    var onFoodCleared: (() -> Void)?

    /// Callback when a generative AI search completes (triggered by natural language
    /// detected in the text field, e.g. from iOS keyboard dictation).
    var onGenerativeSearchResult: ((AIFoodAnalysisResult) -> Void)?

    // MARK: - Food Search Published Properties

    /// Current search text for food lookup
    @Published var foodSearchText: String = ""

    /// Results from food search
    @Published var foodSearchResults: [OpenFoodFactsProduct] = []

    /// Currently selected food product
    @Published var selectedFoodProduct: OpenFoodFactsProduct? = nil

    /// Pre-downloaded product thumbnail image (avoids AsyncImage rebuild issues)
    @Published var productThumbnailImage: UIImage? = nil

    /// Serving size context for selected food product
    @Published var selectedFoodServingSize: String? = nil

    /// Number of servings for the selected food product
    @Published var numberOfServings: Double = 1.0

    /// Whether a food search is currently in progress
    @Published var isFoodSearching: Bool = false

    /// Whether the current search is an AI generative analysis (voice/dictation)
    @Published var isAISearching: Bool = false

    /// Error message from food search operations
    @Published var foodSearchError: String? = nil

    /// Whether the food search UI is visible
    @Published var showingFoodSearch: Bool = false

    /// Flag set when iOS keyboard dictation is detected via DictationAwareTextField.
    /// Causes the next search to route through AI generative search regardless of word count.
    var lastInputWasDictated: Bool = false

    /// Store the last AI analysis result for detailed UI display
    @Published var lastAIAnalysisResult: AIFoodAnalysisResult? = nil

    /// Indices of AI-detected items excluded by the user (soft delete)
    @Published var excludedAIItemIndices: Set<Int> = []

    /// Store the captured AI image for display
    @Published var capturedAIImage: UIImage? = nil

    // MARK: - Internal / Private State

    /// Track the last barcode we searched for to prevent duplicates
    private var lastBarcodeSearched: String? = nil

    /// Flag to track if food search observers have been set up
    private var observersSetUp = false

    /// Search result cache for improved performance
    private var searchCache: [String: CachedSearchResult] = [:]

    /// Cache entry with timestamp for expiration
    private struct CachedSearchResult {
        let results: [OpenFoodFactsProduct]
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300 // 5 minutes cache
        }
    }

    /// OpenFoodFacts service for food search
    private let openFoodFactsService = OpenFoodFactsService()

    /// AI service for provider routing
    private let aiService = ConfigurableAIService.shared

    /// Combine subscriptions
    private lazy var cancellables = Set<AnyCancellable>()

    // MARK: - Absorption Time Context
    // These are passed from the host so this ViewModel can compute
    // absorption-time adjustments without depending on CarbEntryViewModel.

    let defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes

    /// The absorption time currently shown in the host's UI.
    /// Updated via the callback – we keep a local copy so deletion /
    /// recalculation logic can reference it.
    @Published var absorptionTime: TimeInterval

    /// Whether the absorption time was set by AI analysis
    @Published var absorptionTimeWasAIGenerated: Bool = false

    /// Internal flag so programmatic absorption-time writes don't flip
    /// ``absorptionTimeWasEdited`` in the host.
    internal var absorptionEditIsProgrammatic = false

    // MARK: - Associated-Object Storage for Task

    /// Task for debounced search operations
    private var foodSearchTask: Task<Void, Never>? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.foodSearchTask) as? Task<Void, Never> }
        set { objc_setAssociatedObject(self, &AssociatedKeys.foodSearchTask, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    private struct AssociatedKeys {
        static var foodSearchTask: UInt8 = 0
    }

    // MARK: - Init

    /// - Parameters:
    ///   - defaultAbsorptionTimes: The fast / medium / slow absorption times from the CarbStore.
    ///   - initialAbsorptionTime: Current absorption time from the host (usually `medium`).
    init(defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes,
         initialAbsorptionTime: TimeInterval) {
        self.defaultAbsorptionTimes = defaultAbsorptionTimes
        self.absorptionTime = initialAbsorptionTime
    }

    // MARK: - Observer Setup

    /// Call once after init (typically from the hosting view's onAppear or
    /// the parent ViewModel's init).
    func setupObservers() {
        setupFoodSearchObservers()
        observeNumberOfServingsChange()
        observeAIExclusionsChange()
    }

    /// Setup food search observers
    func setupFoodSearchObservers() {
        guard !observersSetUp else {
            return
        }

        observersSetUp = true

        // Debounce search text changes
        $foodSearchText
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] searchText in
                self?.performFoodSearch(query: searchText)
            }
            .store(in: &cancellables)

        // Listen for barcode scan results with deduplication
        BarcodeScannerService.shared.$lastScanResult
            .compactMap { $0 }
            .removeDuplicates { $0.barcodeString == $1.barcodeString }
            .throttle(for: .milliseconds(800), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] result in
                print("🔍 ========== BARCODE RECEIVED IN VIEWMODEL ==========")
                print("🔍 FoodFinder_SearchViewModel received barcode from BarcodeScannerService: \(result.barcodeString)")
                print("🔍 Barcode confidence: \(result.confidence)")
                print("🔍 Calling searchFoodProductByBarcode...")
                // Consume the scan result immediately so other subscribers
                // (e.g. from SwiftUI view recreation) don't re-process the same barcode.
                BarcodeScannerService.shared.lastScanResult = nil
                self?.searchFoodProductByBarcode(result.barcodeString)
            }
            .store(in: &cancellables)
    }

    // MARK: - Servings / AI Exclusion Observers

    private func observeNumberOfServingsChange() {
        $numberOfServings
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] servings in
                print("🥄 numberOfServings changed to: \(servings), recalculating nutrition...")
                self?.recalculateCarbsForServings(servings)
                self?.recomputeAIAdjustments()
            }
            .store(in: &cancellables)
    }

    private func observeAIExclusionsChange() {
        $excludedAIItemIndices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recomputeAIAdjustments()
            }
            .store(in: &cancellables)
        $lastAIAnalysisResult
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recomputeAIAdjustments()
            }
            .store(in: &cancellables)
    }

    // MARK: - AI Adjustment Recomputation

    /// Recompute carbs and absorption time based on included AI items
    func recomputeAIAdjustments() {
        guard let ai = lastAIAnalysisResult else { return }
        let included = ai.foodItemsDetailed.enumerated()
            .filter { !excludedAIItemIndices.contains($0.offset) }
            .map { $0.element }
        // Carbs
        let baseCarbs = included.reduce(0.0) { $0 + $1.carbohydrates }
        let scale = ai.originalServings > 0 ? (numberOfServings / ai.originalServings) : 1.0
        let newCarbs = baseCarbs * scale

        // Absorption time: use overall AI time if present (per-item times not available)
        var newAbsorptionTime = absorptionTime
        var aiGenerated = absorptionTimeWasAIGenerated
        if let hours = ai.absorptionTimeHours, hours > 0 {
            newAbsorptionTime = TimeInterval(hours * 3600)
            aiGenerated = true
        }

        // Determine food type from the AI result
        let foodType: String = {
            let names = included.map { $0.name }
            if names.count == 1 {
                return names[0]
            } else if !names.isEmpty {
                let joined = names.joined(separator: ", ")
                if joined.count > 20 {
                    return String(joined.prefix(19)) + "…"
                }
                return joined
            }
            return ai.overallDescription ?? "AI Analysis"
        }()

        // Notify host
        absorptionEditIsProgrammatic = true
        absorptionTime = newAbsorptionTime
        absorptionTimeWasAIGenerated = aiGenerated

        onNutritionApplied?(FoodFinder_NutritionResult(
            carbs: newCarbs,
            foodType: foodType,
            absorptionTime: newAbsorptionTime,
            absorptionTimeWasAIGenerated: aiGenerated
        ))
    }

    // MARK: - Voice / Generative Search

    /// Perform a generative AI food search from voice-transcribed text.
    /// Routes through the AI image analysis pipeline (same prompt) instead
    /// of the USDA text search, enabling natural-language food descriptions
    /// like "a medium bowl of spicy ramen and a side of gyoza".
    @MainActor
    func performVoiceSearch(query: String) async -> AIFoodAnalysisResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        print("🎙️ Starting generative voice search for: '\(trimmed)'")

        isFoodSearching = true
        isAISearching = true
        foodSearchError = nil
        foodSearchResults = []
        showingFoodSearch = true

        defer {
            isFoodSearching = false
            isAISearching = false
        }

        do {
            let result = try await foodFinder_withTimeout(seconds: 60) {
                try await FoodSearchRouter.shared.analyzeFoodByDescription(trimmed)
            }

            print("🎙️ Voice search AI analysis completed for: '\(trimmed)' — carbs: \(result.totalCarbohydrates)g")

            // Clear skeleton results
            foodSearchResults = []
            showingFoodSearch = false

            return result
        } catch {
            print("🎙️ Voice search failed: \(error.localizedDescription)")

            if error is CancellationError { return nil }

            foodSearchError = "AI analysis failed: \(error.localizedDescription). Try typing your search instead."
            foodSearchResults = []
            return nil
        }
    }

    // MARK: - Natural Language Detection

    /// Heuristic to detect natural language food descriptions (likely from iOS keyboard dictation).
    /// Short keyword queries like "apple" or "chicken soup" go to USDA; longer descriptive
    /// phrases like "a medium bowl of spicy ramen and a side of gyoza" go to AI.
    private func isNaturalLanguageQuery(_ query: String) -> Bool {
        let words = query.split(separator: " ").filter { !$0.isEmpty }
        guard words.count >= 4 else { return false }

        let lowered = query.lowercased()

        // Explicit natural language indicators (common in dictated speech)
        let indicators = [
            "i'm eating", "i ate", "i had", "i'm having", "i just had", "i just ate",
            "a bowl of", "a plate of", "a cup of", "a glass of", "a piece of", "a slice of",
            "a medium", "a large", "a small", "with a side", "and a side", "and a",
            "for lunch", "for dinner", "for breakfast", "some "
        ]
        for indicator in indicators {
            if lowered.contains(indicator) { return true }
        }

        // 5+ words without explicit indicators is still likely a descriptive phrase
        return words.count >= 5
    }

    // MARK: - Food Search Methods

    /// Perform food search with given query
    /// - Parameter query: Search term for food lookup
    func performFoodSearch(query: String) {

        // Cancel previous search
        foodSearchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clear results if query is empty
        guard !trimmedQuery.isEmpty else {
            foodSearchResults = []
            foodSearchError = nil
            showingFoodSearch = false
            return
        }

        print("🔍 Starting search for: '\(trimmedQuery)'")

        // Detect dictation (via DictationAwareTextField flag) or natural language input and route to AI
        let wasDictated = lastInputWasDictated
        if wasDictated {
            lastInputWasDictated = false  // Reset flag immediately
        }

        if wasDictated || isNaturalLanguageQuery(trimmedQuery) {
            print("🎙️ \(wasDictated ? "Dictation detected" : "Natural language detected") — routing to AI generative search for: '\(trimmedQuery)'")
            foodSearchTask = Task { [weak self] in
                guard let self = self else { return }
                if let result = await self.performVoiceSearch(query: trimmedQuery) {
                    await MainActor.run {
                        self.onGenerativeSearchResult?(result)
                    }
                }
            }
            return
        }

        // Show search UI, clear previous results and error
        showingFoodSearch = true
        foodSearchResults = []  // Clear previous results to show searching state
        foodSearchError = nil
        isFoodSearching = true

        // Perform new search immediately but ensure minimum search time for UX
        foodSearchTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                await self.searchFoodProducts(query: trimmedQuery)
            } catch {
                print("🔍 Food search error: \(error)")
                await MainActor.run {
                    self.foodSearchError = error.localizedDescription
                    self.isFoodSearching = false
                }
            }
        }
    }

    /// Search for food products using OpenFoodFacts API
    /// - Parameter query: Search query string
    @MainActor
    private func searchFoodProducts(query: String) async {
        print("🔍 searchFoodProducts starting for: '\(query)'")
        foodSearchError = nil

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Check cache first for instant results
        if let cachedResult = searchCache[trimmedQuery], !cachedResult.isExpired {
            print("🔍 Using cached results for: '\(trimmedQuery)'")
            foodSearchResults = cachedResult.results
            isFoodSearching = false
            return
        }

        // Show skeleton loading state immediately
        foodSearchResults = createSkeletonResults()

        let searchStartTime = Date()
        let minimumSearchDuration: TimeInterval = 0.3 // Reduced from 1.2s for better responsiveness

        do {
            print("🔍 Performing text search with configured provider...")
            let rawProducts = try await performTextSearch(query: query)

            // Sort results by relevance so the most obvious match appears first
            let products = sortByRelevance(rawProducts, query: trimmedQuery)

            // Cache the sorted results for future use
            searchCache[trimmedQuery] = CachedSearchResult(results: products, timestamp: Date())
            print("🔍 Cached results for: '\(trimmedQuery)' (\(products.count) items)")

            // Periodically clean up expired cache entries
            if searchCache.count > 20 {
                cleanupExpiredCache()
            }

            // Ensure minimum search duration for smooth animations
            let elapsedTime = Date().timeIntervalSince(searchStartTime)
            if elapsedTime < minimumSearchDuration {
                let remainingTime = minimumSearchDuration - elapsedTime
                print("🔍 Adding \(remainingTime)s delay to reach minimum search duration")
                do {
                    try await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
                } catch {
                    // Task.sleep can throw CancellationError, which is fine to ignore for timing
                    print("🔍 Task.sleep cancelled during search timing (expected)")
                }
            }

            foodSearchResults = products

            print("🔍 Search completed! Found \(products.count) products")

            os_log("Food search for '%{public}@' returned %d results",
                   log: OSLog(category: "FoodSearch"),
                   type: .info,
                   query,
                   products.count)

        } catch {
            print("🔍 Search failed with error: \(error)")

            // Don't show cancellation errors to the user - they're expected during rapid typing
            if error is CancellationError {
                print("🔍 Search was cancelled (expected behavior)")
                // Clear any previous error when cancelled
                foodSearchError = nil
                isFoodSearching = false
                return
            }

            // Check for URLError cancellation as well
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("🔍 URLSession request was cancelled (expected behavior)")
                // Clear any previous error when cancelled
                foodSearchError = nil
                isFoodSearching = false
                return
            }

            // Check for OpenFoodFactsError wrapping a URLError cancellation
            if let openFoodFactsError = error as? OpenFoodFactsError,
               case .networkError(let underlyingError) = openFoodFactsError,
               let urlError = underlyingError as? URLError,
               urlError.code == .cancelled {
                print("🔍 OpenFoodFacts wrapped URLSession request was cancelled (expected behavior)")
                // Clear any previous error when cancelled
                foodSearchError = nil
                isFoodSearching = false
                return
            }

            // For real errors, ensure minimum search duration before showing error
            let elapsedTime = Date().timeIntervalSince(searchStartTime)
            if elapsedTime < minimumSearchDuration {
                let remainingTime = minimumSearchDuration - elapsedTime
                print("🔍 Adding \(remainingTime)s delay before showing error")
                do {
                    try await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
                } catch {
                    // Task.sleep can throw CancellationError, which is fine to ignore for timing
                    print("🔍 Task.sleep cancelled during error timing (expected)")
                }
            }

            foodSearchError = error.localizedDescription
            foodSearchResults = []

            os_log("Food search failed: %{public}@",
                   log: OSLog(category: "FoodSearch"),
                   type: .error,
                   error.localizedDescription)
        }

        // Always set isFoodSearching to false at the end
        isFoodSearching = false
        print("🔍 searchFoodProducts finished, isFoodSearching = false")
    }

    // MARK: - Barcode Search

    /// Search for a specific product by barcode
    /// - Parameter barcode: Product barcode

    func searchFoodProductByBarcode(_ barcode: String) {
        print("🔍 ========== BARCODE SEARCH STARTED ==========")
        print("🔍 searchFoodProductByBarcode called with barcode: \(barcode)")
        print("🔍 Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
        print("🔍 lastBarcodeSearched: \(lastBarcodeSearched ?? "nil")")

        // Prevent duplicate searches for the same barcode
        if let lastBarcode = lastBarcodeSearched, lastBarcode == barcode {
            print("🔍 ⚠️ Ignoring duplicate barcode search for: \(barcode)")
            return
        }

        // Always cancel any existing task to prevent stalling
        if let existingTask = foodSearchTask, !existingTask.isCancelled {
            print("🔍 Cancelling existing search task")
            existingTask.cancel()
        }

        lastBarcodeSearched = barcode

        foodSearchTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                print("🔍 Starting barcode lookup task for: \(barcode)")

                // Add timeout wrapper to prevent infinite stalling
                try await foodFinder_withTimeout(seconds: 45) {
                    await self.lookupProductByBarcode(barcode)
                }

                // Clear the last barcode after successful completion
                await MainActor.run {
                    self.lastBarcodeSearched = nil
                }
            } catch {
                print("🔍 Barcode search error: \(error)")

                await MainActor.run {
                    // If it's a timeout, create fallback product
                    if error is FoodFinder_TimeoutError {
                        print("🔍 Barcode search timed out, creating fallback product")
                        self.createManualEntryPlaceholder(for: barcode)
                        self.lastBarcodeSearched = nil
                        return
                    }

                    self.foodSearchError = error.localizedDescription
                    self.isFoodSearching = false

                    // Clear the last barcode after error
                    self.lastBarcodeSearched = nil
                }
            }
        }
    }

    /// Look up a product by barcode
    /// - Parameter barcode: Product barcode
    @MainActor
    private func lookupProductByBarcode(_ barcode: String) async {
        print("🔍 lookupProductByBarcode starting for: \(barcode)")

        // Clear previous results to show searching state
        foodSearchResults = []
        isFoodSearching = true
        foodSearchError = nil

        defer {
            print("🔍 lookupProductByBarcode finished, setting isFoodSearching = false")
            isFoodSearching = false
        }

        // Quick network connectivity check - if we can't reach the API quickly, show clear error
        do {
            print("🔍 Testing OpenFoodFacts connectivity...")
            let testUrl = URL(string: "https://world.openfoodfacts.net/api/v2/product/test.json")!
            var testRequest = URLRequest(url: testUrl)
            testRequest.timeoutInterval = 3.0  // Very short timeout for connectivity test
            testRequest.httpMethod = "HEAD"  // Just check if server responds

            let (_, response) = try await URLSession.shared.data(for: testRequest)
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 OpenFoodFacts connectivity test: HTTP \(httpResponse.statusCode)")
                if httpResponse.statusCode >= 500 {
                    throw URLError(.badServerResponse)
                }
            }
        } catch {
            print("🔍 OpenFoodFacts not reachable: \(error)")
            // Offer to create a manual entry placeholder
            createManualEntryPlaceholder(for: barcode)
            return
        }

        do {
            print("🔍 Calling performBarcodeSearch for: \(barcode)")
            if let product = try await performBarcodeSearch(barcode: barcode) {
                // Add to search results and select it
                if !foodSearchResults.contains(product) {
                    foodSearchResults.insert(product, at: 0)
                }
                selectFoodProduct(product)

                os_log("Barcode lookup successful for %{public}@: %{public}@",
                       log: OSLog(category: "FoodSearch"),
                       type: .info,
                       barcode,
                       product.displayName)
            } else {
                print("🔍 No product found, creating manual entry placeholder")
                createManualEntryPlaceholder(for: barcode)
            }

        } catch {
            // Don't show cancellation errors to the user - just return without doing anything
            if error is CancellationError {
                print("🔍 Barcode lookup was cancelled (expected behavior)")
                foodSearchError = nil
                return
            }

            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("🔍 Barcode lookup URLSession request was cancelled (expected behavior)")
                foodSearchError = nil
                return
            }

            // Check for OpenFoodFactsError wrapping a URLError cancellation
            if let openFoodFactsError = error as? OpenFoodFactsError,
               case .networkError(let underlyingError) = openFoodFactsError,
               let urlError = underlyingError as? URLError,
               urlError.code == .cancelled {
                print("🔍 Barcode lookup OpenFoodFacts wrapped URLSession request was cancelled (expected behavior)")
                foodSearchError = nil
                return
            }

            // For any other error (network issues, product not found, etc.), create manual entry placeholder
            print("🔍 Barcode lookup failed with error: \(error), creating manual entry placeholder")
            createManualEntryPlaceholder(for: barcode)

            os_log("Barcode lookup failed for %{public}@: %{public}@, created manual entry placeholder",
                   log: OSLog(category: "FoodSearch"),
                   type: .info,
                   barcode,
                   error.localizedDescription)
        }
    }

    /// Create a manual entry placeholder when network requests fail
    /// - Parameter barcode: The scanned barcode
    private func createManualEntryPlaceholder(for barcode: String) {
        print("🔍 ========== CREATING MANUAL ENTRY PLACEHOLDER ==========")
        print("🔍 Creating manual entry placeholder for barcode: \(barcode)")
        print("🔍 Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
        print("🔍 ⚠️ WARNING: This is NOT real product data - requires manual entry")

        // Create a placeholder product that requires manual nutrition entry
        let fallbackProduct = OpenFoodFactsProduct(
            id: "fallback_\(barcode)",
            productName: "Product \(barcode)",
            brands: "Database Unavailable",
            categories: "⚠️ NUTRITION DATA UNAVAILABLE - ENTER MANUALLY",
            nutriments: Nutriments(
                carbohydrates: 0.0,  // Force user to enter real values
                proteins: 0.0,
                fat: 0.0,
                calories: 0.0,
                sugars: nil,
                fiber: nil
            ),
            servingSize: "Enter serving size",
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontURL: nil,
            code: barcode,
            dataSource: .barcodeScan
        )

        // Add to search results and select it
        if !foodSearchResults.contains(fallbackProduct) {
            foodSearchResults.insert(fallbackProduct, at: 0)
        }

        selectFoodProduct(fallbackProduct)

        // Store the selected food information for UI display
        selectedFoodServingSize = fallbackProduct.servingSize
        numberOfServings = 1.0

        // Clear any error since we successfully created a fallback
        foodSearchError = nil

        print("🔍 ✅ Manual entry placeholder created for barcode: \(barcode)")
        print("🔍 foodSearchResults.count: \(foodSearchResults.count)")
        print("🔍 selectedFoodProduct: \(selectedFoodProduct?.displayName ?? "nil")")
        print("🔍 ========== MANUAL ENTRY PLACEHOLDER COMPLETE ==========")
    }

    // MARK: - Select Food Product

    /// Select a food product and populate carb entry fields
    /// - Parameter product: The selected food product
    func selectFoodProduct(_ product: OpenFoodFactsProduct) {
        print("🔄 ========== SELECTING FOOD PRODUCT ==========")
        print("🔄 Product: \(product.displayName)")
        print("🔄 Product ID: \(product.id)")
        print("🔄 Data source: \(product.dataSource)")
        print("🔄 Current absorptionTime BEFORE selecting: \(absorptionTime)")

        selectedFoodProduct = product
        downloadProductThumbnail(for: product)

        // Populate food type (truncate to 20 chars to fit RowEmojiTextField maxLength)
        let maxFoodTypeLength = 20
        let foodType: String
        if product.displayName.count > maxFoodTypeLength {
            let truncatedName = String(product.displayName.prefix(maxFoodTypeLength - 1)) + "…"
            foodType = truncatedName
        } else {
            foodType = product.displayName
        }

        // Store serving size context for display
        selectedFoodServingSize = product.servingSizeDisplay

        // Start with 1 serving (user can adjust)
        numberOfServings = 1.0

        // Calculate carbs - but only for real products with valid data
        let carbsQuantity: Double?
        if product.id.hasPrefix("fallback_") {
            // This is a fallback product - don't auto-populate any nutrition data
            carbsQuantity = nil  // Force user to enter manually
            print("🔍 ⚠️ Fallback product selected - carbs must be entered manually")
        } else if let carbsPerServing = product.carbsPerServing {
            carbsQuantity = carbsPerServing * numberOfServings
        } else if product.nutriments.carbohydrates > 0 {
            // Use carbs per 100g as base, user can adjust
            carbsQuantity = product.nutriments.carbohydrates * numberOfServings
        } else {
            // No carb data available
            carbsQuantity = nil
        }

        print("🔄 Current absorptionTime AFTER all processing: \(absorptionTime)")
        print("🔄 ========== FOOD PRODUCT SELECTION COMPLETE ==========")

        // Clear search UI but keep selected product
        foodSearchText = ""
        foodSearchResults = []
        foodSearchError = nil
        showingFoodSearch = false
        foodSearchTask?.cancel()

        // Clear AI-specific state when selecting a non-AI product
        // This ensures AI results don't persist when switching to text/barcode search
        if !product.id.hasPrefix("ai_") {
            lastAIAnalysisResult = nil
            capturedAIImage = nil
            absorptionTimeWasAIGenerated = false  // Clear AI absorption time flag for non-AI products
            os_log("🔄 Cleared AI analysis state when selecting non-AI product: %{public}@",
                   log: OSLog(category: "FoodSearch"),
                   type: .info,
                   product.id)
        }

        os_log("Selected food product: %{public}@ with %{public}g carbs per %{public}@ for %{public}.1f servings",
               log: OSLog(category: "FoodSearch"),
               type: .info,
               product.displayName,
               carbsQuantity ?? 0,
               selectedFoodServingSize ?? "serving",
               numberOfServings)

        // Notify the host about the selection
        onNutritionApplied?(FoodFinder_NutritionResult(
            carbs: carbsQuantity ?? 0,
            foodType: foodType,
            absorptionTime: absorptionTime,
            absorptionTimeWasAIGenerated: absorptionTimeWasAIGenerated
        ))
    }

    // MARK: - Product Thumbnail Download

    /// Eagerly download the product thumbnail so the view can use a cached UIImage
    /// instead of AsyncImage (which restarts on every SwiftUI view rebuild).
    private func downloadProductThumbnail(for product: OpenFoodFactsProduct) {
        productThumbnailImage = nil
        let urlString = product.imageFrontSmallURL ?? product.imageFrontURL ?? product.imageURL
        guard let urlString, !urlString.isEmpty else { return }

        // Prefer the smallest OpenFoodFacts thumbnail (100px) for fast loading.
        // OFF URLs follow the pattern: .../front_en.REV.SIZE.jpg
        // Rewrite .200.jpg or .400.jpg → .100.jpg for a much smaller file.
        let thumbURLString: String
        if urlString.contains("openfoodfacts.org") {
            thumbURLString = urlString
                .replacingOccurrences(of: ".200.jpg", with: ".100.jpg")
                .replacingOccurrences(of: ".400.jpg", with: ".100.jpg")
        } else {
            thumbURLString = urlString
        }

        guard let url = URL(string: thumbURLString) else { return }
        Task {
            let image = await ImageDownloader.fetchThumbnail(from: url, maxDimension: 120)
            await MainActor.run {
                // Only set if this product is still selected
                if self.selectedFoodProduct?.id == product.id {
                    self.productThumbnailImage = image
                }
            }
        }
    }

    // MARK: - Recalculate Carbs for Servings

    /// Recalculate carbohydrates based on number of servings
    /// - Parameter servings: Number of servings
    private func recalculateCarbsForServings(_ servings: Double) {
        guard let selectedFood = selectedFoodProduct else {
            print("🥄 recalculateCarbsForServings: No selected food product")
            return
        }

        print("🥄 recalculateCarbsForServings: servings=\(servings), selectedFood=\(selectedFood.displayName)")

        // Calculate carbs based on servings - prefer per serving, fallback to per 100g
        let newCarbsQuantity: Double
        if let carbsPerServing = selectedFood.carbsPerServing {
            newCarbsQuantity = carbsPerServing * servings
            print("🥄 Using carbsPerServing: \(carbsPerServing) * \(servings) = \(newCarbsQuantity)")
        } else {
            newCarbsQuantity = selectedFood.nutriments.carbohydrates * servings
            print("🥄 Using nutriments.carbohydrates: \(selectedFood.nutriments.carbohydrates) * \(servings) = \(newCarbsQuantity)")
        }

        print("🥄 Final carbsQuantity set to: \(newCarbsQuantity)")

        // Determine food type from the selected product
        let maxFoodTypeLength = 20
        let foodType: String
        if selectedFood.displayName.count > maxFoodTypeLength {
            foodType = String(selectedFood.displayName.prefix(maxFoodTypeLength - 1)) + "…"
        } else {
            foodType = selectedFood.displayName
        }

        // Notify host of the updated carbs
        onNutritionApplied?(FoodFinder_NutritionResult(
            carbs: newCarbsQuantity,
            foodType: foodType,
            absorptionTime: absorptionTime,
            absorptionTimeWasAIGenerated: absorptionTimeWasAIGenerated
        ))

        os_log("Recalculated carbs for %{public}.1f servings: %{public}g",
               log: OSLog(category: "FoodSearch"),
               type: .info,
               servings,
               newCarbsQuantity)
    }

    // MARK: - Skeleton Loading

    /// Create skeleton loading results for immediate feedback
    private func createSkeletonResults() -> [OpenFoodFactsProduct] {
        return (0..<3).map { index in
            var product = OpenFoodFactsProduct(
                id: "skeleton_\(index)",
                productName: "Loading...",
                brands: "Loading...",
                categories: nil,
                nutriments: Nutriments.empty(),
                servingSize: nil,
                servingQuantity: nil,
                imageURL: nil,
                imageFrontURL: nil,
                code: nil,
                dataSource: .unknown,
                isSkeleton: false
            )
            product.isSkeleton = true  // Set skeleton flag
            return product
        }
    }

    // MARK: - Clear / Toggle Helpers

    /// Clear food search state
    func clearFoodSearch() {
        foodSearchText = ""
        foodSearchResults = []
        selectedFoodProduct = nil
        productThumbnailImage = nil
        selectedFoodServingSize = nil
        foodSearchError = nil
        showingFoodSearch = false
        foodSearchTask?.cancel()
        lastBarcodeSearched = nil  // Allow re-scanning the same barcode
    }

    /// Clean up expired cache entries
    private func cleanupExpiredCache() {
        let expiredKeys = searchCache.compactMap { key, value in
            value.isExpired ? key : nil
        }

        for key in expiredKeys {
            searchCache.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            print("🔍 Cleaned up \(expiredKeys.count) expired cache entries")
        }
    }

    /// Clear search cache manually
    func clearSearchCache() {
        searchCache.removeAll()
        print("🔍 Search cache cleared")
    }

    /// Toggle food search visibility
    func toggleFoodSearch() {
        showingFoodSearch.toggle()

        if !showingFoodSearch {
            clearFoodSearch()
        }
    }

    /// Clear selected food product and its context
    func clearSelectedFood() {
        selectedFoodProduct = nil
        productThumbnailImage = nil
        selectedFoodServingSize = nil
        numberOfServings = 1.0
        lastAIAnalysisResult = nil
        capturedAIImage = nil
        absorptionTimeWasAIGenerated = false  // Clear AI absorption time flag
        lastBarcodeSearched = nil  // Allow re-scanning the same barcode

        os_log("Cleared selected food product",
               log: OSLog(category: "FoodSearch"),
               type: .info)

        // Notify host that food was cleared
        onFoodCleared?()
    }

    // MARK: - Relevance Sorting

    /// Sort search results so the most obvious/generic match for the query appears first.
    /// E.g. searching "banana" should show "Banana, raw" before "Yogurt Bnine BANANA".
    private func sortByRelevance(_ products: [OpenFoodFactsProduct], query: String) -> [OpenFoodFactsProduct] {
        let q = query.lowercased()

        return products.sorted { a, b in
            relevanceScore(for: a, query: q) > relevanceScore(for: b, query: q)
        }
    }

    private func relevanceScore(for product: OpenFoodFactsProduct, query: String) -> Int {
        let name = product.displayName.lowercased()
        let nameWords = name.split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
        var score = 0

        // Exact match (e.g. "banana" == "banana")
        if name == query { score += 10000 }

        // Name starts with query word then comma/space (e.g. "banana, raw" or "banana chips")
        if name.hasPrefix(query + ",") || name.hasPrefix(query + " ") { score += 5000 }

        // Name starts with query
        if name.hasPrefix(query) { score += 4000 }

        // First word of name matches query (e.g. "bananas" for "banana")
        if let first = nameWords.first, first.hasPrefix(query) { score += 3000 }

        // Query appears as a standalone word anywhere in the name
        if nameWords.contains(query) { score += 2000 }

        // Prefer shorter, simpler product names (generic foods have fewer words)
        let wordCount = nameWords.count
        if wordCount == 1 { score += 500 }
        else if wordCount == 2 { score += 400 }
        else if wordCount <= 4 { score += 200 }
        else { score -= wordCount * 20 }

        // Penalize products where the query only matches as a substring of another word
        // e.g. "BANANA" inside "Yogurt Bnine BANANA" is fine but
        // rank lower if the product is clearly a different food category
        let queryWords = query.split(separator: " ").map { String($0) }
        if queryWords.count == 1 {
            // Single-word query: penalize if name has many extra words
            let extraWords = wordCount - 1
            score -= extraWords * 30
        }

        // Penalize branded products for simple single-word queries
        if queryWords.count == 1, let brands = product.brands,
           !brands.isEmpty, brands.lowercased() != name {
            score -= 100
        }

        return score
    }

    // MARK: - Provider Routing Methods

    /// Perform text search using configured provider
    private func performTextSearch(query: String) async throws -> [OpenFoodFactsProduct] {
        // Centralize text search routing and fallbacks in FoodSearchRouter
        return try await FoodSearchRouter.shared.searchFoodsByText(query)
    }

    /// Perform barcode search using configured provider
    private func performBarcodeSearch(barcode: String) async throws -> OpenFoodFactsProduct? {
        let provider = aiService.getProviderForSearchType(.barcodeSearch)


        switch provider {
        case .openFoodFacts:
            if let product = try await openFoodFactsService.fetchProduct(barcode: barcode) {
                // Create a new product with the correct dataSource
                return OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    imageFrontSmallURL: product.imageFrontSmallURL,
                    code: product.code,
                    dataSource: .barcodeScan
                )
            }
            return nil

        case .usdaFoodData, .aiProvider:
            // These providers don't support barcode search, fall back to OpenFoodFacts
            if let product = try await openFoodFactsService.fetchProduct(barcode: barcode) {
                return OpenFoodFactsProduct(
                    id: product.id,
                    productName: product.productName,
                    brands: product.brands,
                    categories: product.categories,
                    nutriments: product.nutriments,
                    servingSize: product.servingSize,
                    servingQuantity: product.servingQuantity,
                    imageURL: product.imageURL,
                    imageFrontURL: product.imageFrontURL,
                    imageFrontSmallURL: product.imageFrontSmallURL,
                    code: product.code,
                    dataSource: .barcodeScan
                )
            }
            return nil
        }
    }

    // Provider-specific text search methods removed during BYO migration.
    // Text search now routes through FoodSearchRouter → USDA/OpenFoodFacts.

    /// Creates a small placeholder image for text-based Gemini queries
    private func createPlaceholderImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)

        // Create a simple gradient background
        let context = UIGraphicsGetCurrentContext()!
        let colors = [UIColor.systemBlue.cgColor, UIColor.systemGreen.cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!

        context.drawLinearGradient(gradient, start: CGPoint.zero, end: CGPoint(x: size.width, y: size.height), options: [])

        // Add a food icon in the center
        let iconSize: CGFloat = 40
        let iconFrame = CGRect(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )

        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: iconFrame)

        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()

        return image
    }

    // MARK: - Food Item Management

    func deleteFoodItem(at index: Int) {
        guard var currentResult = lastAIAnalysisResult,
              index >= 0 && index < currentResult.foodItemsDetailed.count else {
            print("⚠️ Cannot delete food item: invalid index \(index) or no AI analysis result")
            return
        }

        print("🗑️ Deleting food item at index \(index): \(currentResult.foodItemsDetailed[index].name)")

        // Remove the item from the array (now possible since foodItemsDetailed is var)
        currentResult.foodItemsDetailed.remove(at: index)

        // Recalculate totals from remaining items
        let newTotalCarbs = currentResult.foodItemsDetailed.reduce(0) { $0 + $1.carbohydrates }
        let newTotalProtein = currentResult.foodItemsDetailed.compactMap { $0.protein }.reduce(0, +)
        let newTotalFat = currentResult.foodItemsDetailed.compactMap { $0.fat }.reduce(0, +)
        let newTotalFiber = currentResult.foodItemsDetailed.compactMap { $0.fiber }.reduce(0, +)
        let newTotalCalories = currentResult.foodItemsDetailed.compactMap { $0.calories }.reduce(0, +)

        // Update the totals in the current result
        currentResult.totalCarbohydrates = newTotalCarbs
        currentResult.totalProtein = newTotalProtein > 0 ? newTotalProtein : nil
        currentResult.totalFat = newTotalFat > 0 ? newTotalFat : nil
        currentResult.totalFiber = newTotalFiber > 0 ? newTotalFiber : nil
        currentResult.totalCalories = newTotalCalories > 0 ? newTotalCalories : nil

        // Recalculate absorption time if advanced dosing is enabled
        if UserDefaults.standard.foodFinder_advancedDosingRecommendationsEnabled {
            let (newAbsorptionHours, newReasoning) = recalculateAbsorptionTime(
                carbs: newTotalCarbs,
                protein: newTotalProtein,
                fat: newTotalFat,
                fiber: newTotalFiber,
                calories: newTotalCalories,
                remainingItems: currentResult.foodItemsDetailed,
                context: "Adjusted after removing an item"
            )

            currentResult.absorptionTimeHours = newAbsorptionHours
            currentResult.absorptionTimeReasoning = newReasoning

            // Update the UI absorption time if it was previously AI-generated
            if absorptionTimeWasAIGenerated {
                let newAbsorptionTimeInterval = TimeInterval(newAbsorptionHours * 3600)
                absorptionEditIsProgrammatic = true
                absorptionTime = newAbsorptionTimeInterval

                print("🤖 Updated AI absorption time after deletion: \(newAbsorptionHours) hours")
            }
        }

        // Update the stored result
        lastAIAnalysisResult = currentResult

        // Determine food type
        let foodNames = currentResult.foodItemsDetailed.map { $0.name }
        let foodType: String
        if foodNames.count == 1 {
            foodType = foodNames[0]
        } else if !foodNames.isEmpty {
            let joined = foodNames.joined(separator: ", ")
            foodType = joined.count > 20 ? String(joined.prefix(19)) + "…" : joined
        } else {
            foodType = currentResult.overallDescription ?? "AI Analysis"
        }

        // Notify host
        onNutritionApplied?(FoodFinder_NutritionResult(
            carbs: newTotalCarbs,
            foodType: foodType,
            absorptionTime: absorptionTime,
            absorptionTimeWasAIGenerated: absorptionTimeWasAIGenerated
        ))

        print("✅ Food item deleted. New total carbs: \(newTotalCarbs)g")
    }

    /// Ensures we have an absorption time even if the AI response omitted it.
    func ensureAbsorptionTimeForInitialResult(_ result: inout AIFoodAnalysisResult) {
        if let hours = result.absorptionTimeHours, hours > 0 { return }

        let carbs = result.totalCarbohydrates
        let protein = result.totalProtein ?? result.foodItemsDetailed.compactMap { $0.protein }.reduce(0, +)
        let fat = result.totalFat ?? result.foodItemsDetailed.compactMap { $0.fat }.reduce(0, +)
        let fiber = result.totalFiber ?? result.foodItemsDetailed.compactMap { $0.fiber }.reduce(0, +)
        let calories = result.totalCalories ?? result.foodItemsDetailed.compactMap { $0.calories }.reduce(0, +)

        let (hours, reasoning) = recalculateAbsorptionTime(
            carbs: carbs,
            protein: protein,
            fat: fat,
            fiber: fiber,
            calories: calories,
            remainingItems: result.foodItemsDetailed,
            context: "Estimated from meal composition"
        )

        let defaultHours = defaultAbsorptionTimes.medium / 3600
        if abs(hours - defaultHours) < 0.75 {
            return
        }

        result.absorptionTimeHours = hours
        result.absorptionTimeReasoning = reasoning
    }

    // MARK: - Absorption Time Recalculation

    /// Recalculates absorption time based on remaining meal composition using AI dosing logic
    private func recalculateAbsorptionTime(
        carbs: Double,
        protein: Double,
        fat: Double,
        fiber: Double,
        calories: Double,
        remainingItems: [FoodItemAnalysis],
        context: String
    ) -> (hours: Double, reasoning: String) {

        // Base absorption time based on carb complexity
        let baselineHours: Double = carbs <= 15 ? 2.5 : 3.0

        // Calculate Fat/Protein Units (FPUs)
        let fpuValue = (fat + protein) / 10.0
        let fpuAdjustment: Double
        let fpuDescription: String

        if fpuValue < 2.0 {
            fpuAdjustment = 1.0
            fpuDescription = "Low FPU (\(String(format: "%.1f", fpuValue))) - minimal extension"
        } else if fpuValue < 4.0 {
            fpuAdjustment = 2.5
            fpuDescription = "Medium FPU (\(String(format: "%.1f", fpuValue))) - moderate extension"
        } else {
            fpuAdjustment = 4.0
            fpuDescription = "High FPU (\(String(format: "%.1f", fpuValue))) - significant extension"
        }

        // Fiber impact on absorption
        let fiberAdjustment: Double
        let fiberDescription: String

        if fiber > 8.0 {
            fiberAdjustment = 2.0
            fiberDescription = "High fiber (\(String(format: "%.1f", fiber))g) - significantly slows absorption"
        } else if fiber > 5.0 {
            fiberAdjustment = 1.0
            fiberDescription = "Moderate fiber (\(String(format: "%.1f", fiber))g) - moderately slows absorption"
        } else {
            fiberAdjustment = 0.0
            fiberDescription = "Low fiber (\(String(format: "%.1f", fiber))g) - minimal impact"
        }

        // Meal size impact
        let mealSizeAdjustment: Double
        let mealSizeDescription: String

        if calories > 800 {
            mealSizeAdjustment = 2.0
            mealSizeDescription = "Large meal (\(String(format: "%.0f", calories)) cal) - delayed gastric emptying"
        } else if calories > 400 {
            mealSizeAdjustment = 1.0
            mealSizeDescription = "Medium meal (\(String(format: "%.0f", calories)) cal) - moderate impact"
        } else {
            mealSizeAdjustment = 0.0
            mealSizeDescription = "Small meal (\(String(format: "%.0f", calories)) cal) - minimal impact"
        }

        // Calculate total absorption time (capped at reasonable limits)
        let totalHours = min(max(baselineHours + fpuAdjustment + fiberAdjustment + mealSizeAdjustment, 2.0), 8.0)

        // Generate detailed reasoning
        let reasoning = "\(context): " +
                       "BASELINE: \(String(format: "%.1f", baselineHours)) hours for \(String(format: "%.1f", carbs))g carbs. " +
                       "FPU IMPACT: \(fpuDescription) (+\(String(format: "%.1f", fpuAdjustment)) hours). " +
                       "FIBER EFFECT: \(fiberDescription) (+\(String(format: "%.1f", fiberAdjustment)) hours). " +
                       "MEAL SIZE: \(mealSizeDescription) (+\(String(format: "%.1f", mealSizeAdjustment)) hours). " +
                       "TOTAL: \(String(format: "%.1f", totalHours)) hours for remaining meal composition."

        return (totalHours, reasoning)
    }
}
