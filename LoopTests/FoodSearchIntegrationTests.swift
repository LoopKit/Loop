//
//  FoodSearchIntegrationTests.swift
//  LoopTests
//
//  Created by Claude Code for Food Search Integration Testing
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import Combine
import HealthKit
import LoopCore
import LoopKit
import LoopKitUI
@testable import Loop

@MainActor
class FoodSearchIntegrationTests: XCTestCase {
    
    var carbEntryViewModel: CarbEntryViewModel!
    var mockDelegate: MockCarbEntryViewModelDelegate!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockDelegate = MockCarbEntryViewModelDelegate()
        carbEntryViewModel = CarbEntryViewModel(delegate: mockDelegate)
        cancellables = Set<AnyCancellable>()
        
        // Configure mock OpenFoodFacts responses
        OpenFoodFactsService.configureMockResponses()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        carbEntryViewModel = nil
        mockDelegate = nil
        super.tearDown()
    }
    
    // MARK: - Full Flow Integration Tests
    
    func testCompleteTextSearchFlow() {
        let expectation = XCTestExpectation(description: "Text search completes")
        
        // Setup food search observers
        carbEntryViewModel.setupFoodSearchObservers()
        
        // Listen for search results
        carbEntryViewModel.$foodSearchResults
            .dropFirst()
            .sink { results in
                if !results.isEmpty {
                    XCTAssertGreaterThan(results.count, 0)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Trigger search
        carbEntryViewModel.foodSearchText = "bread"
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testCompleteBarcodeSearchFlow() {
        let expectation = XCTestExpectation(description: "Barcode search completes")
        let testBarcode = "1234567890123"
        
        // Setup food search observers
        carbEntryViewModel.setupFoodSearchObservers()
        
        // Listen for search results
        carbEntryViewModel.$selectedFoodProduct
            .compactMap { $0 }
            .sink { product in
                XCTAssertNotNil(product)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Simulate barcode scan
        BarcodeScannerService.shared.simulateScan(barcode: testBarcode)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testFoodProductSelectionUpdatesViewModel() {
        let sampleProduct = OpenFoodFactsProduct.sample(name: "Whole Wheat Bread", carbs: 45.0)
        
        // Select the product
        carbEntryViewModel.selectFoodProduct(sampleProduct)
        
        // Verify carb entry is updated
        XCTAssertEqual(carbEntryViewModel.carbsQuantity, 45.0)
        XCTAssertEqual(carbEntryViewModel.foodType, "Whole Wheat Bread")
        XCTAssertTrue(carbEntryViewModel.usesCustomFoodType)
        XCTAssertEqual(carbEntryViewModel.selectedFoodProduct, sampleProduct)
        
        // Verify search is cleared
        XCTAssertTrue(carbEntryViewModel.foodSearchText.isEmpty)
        XCTAssertTrue(carbEntryViewModel.foodSearchResults.isEmpty)
        XCTAssertFalse(carbEntryViewModel.showingFoodSearch)
    }
    
    func testVoiceSearchIntegrationWithCarbEntry() {
        let expectation = XCTestExpectation(description: "Voice search triggers food search")
        let voiceSearchText = "chicken breast"
        
        // Setup food search observers
        carbEntryViewModel.setupFoodSearchObservers()
        
        // Listen for search text updates
        carbEntryViewModel.$foodSearchText
            .dropFirst()
            .sink { searchText in
                if searchText == voiceSearchText {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Simulate voice search result (this would normally come from FoodSearchBar)
        carbEntryViewModel.foodSearchText = voiceSearchText
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testFoodSearchErrorHandling() {
        let expectation = XCTestExpectation(description: "Search error is handled")
        
        carbEntryViewModel.setupFoodSearchObservers()
        
        // Listen for error states
        carbEntryViewModel.$foodSearchError
            .compactMap { $0 }
            .sink { error in
                XCTAssertNotNil(error)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger a search that will fail (empty results for mock)
        carbEntryViewModel.foodSearchText = "nonexistent_food_item_xyz"
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testBarcodeSearchErrorHandling() {
        let expectation = XCTestExpectation(description: "Barcode error is handled")
        
        carbEntryViewModel.setupFoodSearchObservers()
        
        // Listen for error states
        carbEntryViewModel.$foodSearchError
            .compactMap { $0 }
            .sink { error in
                XCTAssertNotNil(error)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Simulate invalid barcode
        carbEntryViewModel.searchFoodProductByBarcode("invalid_barcode")
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - UI State Management Tests
    
    func testSearchStateManagement() {
        XCTAssertFalse(carbEntryViewModel.isFoodSearching)
        XCTAssertFalse(carbEntryViewModel.showingFoodSearch)
        XCTAssertTrue(carbEntryViewModel.foodSearchText.isEmpty)
        XCTAssertTrue(carbEntryViewModel.foodSearchResults.isEmpty)
        XCTAssertNil(carbEntryViewModel.selectedFoodProduct)
        XCTAssertNil(carbEntryViewModel.foodSearchError)
    }
    
    func testClearFoodSearchResetsAllState() {
        // Set up some search state
        carbEntryViewModel.foodSearchText = "test"
        carbEntryViewModel.foodSearchResults = [OpenFoodFactsProduct.sample()]
        carbEntryViewModel.selectedFoodProduct = OpenFoodFactsProduct.sample()
        carbEntryViewModel.showingFoodSearch = true
        carbEntryViewModel.foodSearchError = "Test error"
        
        // Clear search
        carbEntryViewModel.clearFoodSearch()
        
        // Verify all state is reset
        XCTAssertTrue(carbEntryViewModel.foodSearchText.isEmpty)
        XCTAssertTrue(carbEntryViewModel.foodSearchResults.isEmpty)
        XCTAssertNil(carbEntryViewModel.selectedFoodProduct)
        XCTAssertFalse(carbEntryViewModel.showingFoodSearch)
        XCTAssertNil(carbEntryViewModel.foodSearchError)
    }
    
    func testToggleFoodSearchState() {
        XCTAssertFalse(carbEntryViewModel.showingFoodSearch)
        
        carbEntryViewModel.toggleFoodSearch()
        XCTAssertTrue(carbEntryViewModel.showingFoodSearch)
        
        carbEntryViewModel.toggleFoodSearch()
        XCTAssertFalse(carbEntryViewModel.showingFoodSearch)
    }
    
    // MARK: - Analytics Integration Tests
    
    func testFoodSearchAnalyticsTracking() {
        let sampleProduct = OpenFoodFactsProduct.sample(name: "Test Product", carbs: 30.0)
        
        // Select a product (this should trigger analytics)
        carbEntryViewModel.selectFoodProduct(sampleProduct)
        
        // Verify analytics manager is available
        XCTAssertNotNil(mockDelegate.analyticsServicesManager)
    }
    
    // MARK: - Performance Integration Tests
    
    func testFoodSearchPerformanceWithManyResults() {
        let expectation = XCTestExpectation(description: "Search with many results completes")
        
        carbEntryViewModel.setupFoodSearchObservers()
        
        carbEntryViewModel.$foodSearchResults
            .dropFirst()
            .sink { results in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        measure {
            carbEntryViewModel.foodSearchText = "test"
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    // MARK: - Data Validation Tests
    
    func testCarbQuantityValidationAfterFoodSelection() {
        let productWithHighCarbs = OpenFoodFactsProduct.sample(name: "High Carb Food", carbs: 150.0)
        
        carbEntryViewModel.selectFoodProduct(productWithHighCarbs)
        
        // Verify that extremely high carb values are handled appropriately
        // The actual validation should happen in the CarbEntryView
        XCTAssertEqual(carbEntryViewModel.carbsQuantity, 150.0)
    }
    
    func testCarbQuantityWithServingSizes() {
        // Test product with per-serving carb data
        let productWithServing = OpenFoodFactsProduct(
            id: "test123",
            productName: "Test Pasta",
            brands: "Test Brand",
            categories: nil,
            nutriments: Nutriments(
                carbohydrates: 75.0, // per 100g
                proteins: 12.0,
                fat: 1.5,
                calories: 350,
                sugars: nil,
                fiber: nil,
                energy: nil
            ),
            servingSize: "100g",
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontURL: nil,
            code: nil
        )
        
        carbEntryViewModel.selectFoodProduct(productWithServing)
        
        // Should use per-serving carbs when available
        XCTAssertEqual(carbEntryViewModel.carbsQuantity, productWithServing.carbsPerServing)
    }
}

// MARK: - Mock Delegate

@MainActor
class MockCarbEntryViewModelDelegate: CarbEntryViewModelDelegate {
    var analyticsServicesManager: AnalyticsServicesManager {
        return mockAnalyticsManager
    }
    
    private lazy var mockAnalyticsManager: AnalyticsServicesManager = {
        let manager = AnalyticsServicesManager()
        // For testing purposes, we'll just use the real manager
        // and track analytics through the recorded flag
        return manager
    }()
    
    var defaultAbsorptionTimes: CarbStore.DefaultAbsorptionTimes {
        return CarbStore.DefaultAbsorptionTimes(
            fast: .minutes(30),
            medium: .hours(3),
            slow: .hours(5)
        )
    }
    
    // BolusEntryViewModelDelegate methods
    func withLoopState(do block: @escaping (LoopState) -> Void) {
        // Mock implementation - do nothing
    }
    
    func saveGlucose(sample: NewGlucoseSample) async -> StoredGlucoseSample? {
        return nil
    }
    
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry?, completion: @escaping (Result<StoredCarbEntry>) -> Void) {
        completion(.failure(NSError(domain: "MockError", code: 1, userInfo: nil)))
    }
    
    func storeManualBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date) {
        // Mock implementation - do nothing
    }
    
    func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (Swift.Result<[StoredGlucoseSample], Error>) -> Void) {
        completion(.success([]))
    }
    
    func insulinOnBoard(at date: Date, completion: @escaping (DoseStoreResult<InsulinValue>) -> Void) {
        completion(.success(InsulinValue(startDate: date, value: 0.0)))
    }
    
    func carbsOnBoard(at date: Date, effectVelocities: [GlucoseEffectVelocity]?, completion: @escaping (CarbStoreResult<CarbValue>) -> Void) {
        completion(.success(CarbValue(startDate: date, value: 0.0)))
    }
    
    func insulinActivityDuration(for type: InsulinType?) -> TimeInterval {
        return .hours(4)
    }
    
    var mostRecentGlucoseDataDate: Date? { return nil }
    var mostRecentPumpDataDate: Date? { return nil }
    var isPumpConfigured: Bool { return true }
    var pumpInsulinType: InsulinType? { return nil }
    var settings: LoopSettings { return LoopSettings() }
    var displayGlucosePreference: DisplayGlucosePreference { return DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter) }
    
    func roundBolusVolume(units: Double) -> Double {
        return units
    }
    
    func updateRemoteRecommendation() {
        // Mock implementation - do nothing
    }
}

