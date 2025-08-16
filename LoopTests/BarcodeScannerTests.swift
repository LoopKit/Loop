//
//  BarcodeScannerTests.swift
//  LoopTests
//
//  Created by Claude Code for Barcode Scanner Testing
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import Vision
import Combine
@testable import Loop

class BarcodeScannerServiceTests: XCTestCase {
    
    var barcodeScannerService: BarcodeScannerService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        barcodeScannerService = BarcodeScannerService.mock()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        barcodeScannerService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testServiceInitialization() {
        XCTAssertNotNil(barcodeScannerService)
        XCTAssertFalse(barcodeScannerService.isScanning)
        XCTAssertNil(barcodeScannerService.lastScanResult)
        XCTAssertNil(barcodeScannerService.scanError)
    }
    
    func testSharedInstanceExists() {
        let sharedInstance = BarcodeScannerService.shared
        XCTAssertNotNil(sharedInstance)
    }
    
    // MARK: - Mock Testing
    
    func testSimulateSuccessfulScan() {
        let expectation = XCTestExpectation(description: "Barcode scan result received")
        let testBarcode = "1234567890123"
        
        barcodeScannerService.$lastScanResult
            .compactMap { $0 }
            .sink { result in
                XCTAssertEqual(result.barcodeString, testBarcode)
                XCTAssertGreaterThan(result.confidence, 0.0)
                XCTAssertEqual(result.barcodeType, .ean13)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        barcodeScannerService.simulateScan(barcode: testBarcode)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testSimulateScanError() {
        let expectation = XCTestExpectation(description: "Scan error received")
        let testError = BarcodeScanError.invalidBarcode
        
        barcodeScannerService.$scanError
            .compactMap { $0 }
            .sink { error in
                XCTAssertEqual(error.localizedDescription, testError.localizedDescription)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        barcodeScannerService.simulateError(testError)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testScanningStateUpdates() {
        let expectation = XCTestExpectation(description: "Scanning state updated")
        
        barcodeScannerService.$isScanning
            .dropFirst() // Skip initial value
            .sink { isScanning in
                XCTAssertFalse(isScanning) // Should be false after simulation
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        barcodeScannerService.simulateScan(barcode: "test")
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Error Testing
    
    func testBarcodeScanErrorTypes() {
        let errors: [BarcodeScanError] = [
            .cameraNotAvailable,
            .cameraPermissionDenied,
            .scanningFailed("Test failure"),
            .invalidBarcode,
            .sessionSetupFailed
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertNotNil(error.recoverySuggestion)
        }
    }
    
    func testErrorDescriptionsAreLocalized() {
        let error = BarcodeScanError.cameraPermissionDenied
        let description = error.errorDescription
        
        XCTAssertNotNil(description)
        XCTAssertFalse(description!.isEmpty)
        
        let suggestion = error.recoverySuggestion
        XCTAssertNotNil(suggestion)
        XCTAssertFalse(suggestion!.isEmpty)
    }
}

// MARK: - BarcodeScanResult Tests

class BarcodeScanResultTests: XCTestCase {
    
    func testBarcodeScanResultInitialization() {
        let barcode = "1234567890123"
        let barcodeType = VNBarcodeSymbology.ean13
        let confidence: Float = 0.95
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        
        let result = BarcodeScanResult(
            barcodeString: barcode,
            barcodeType: barcodeType,
            confidence: confidence,
            bounds: bounds
        )
        
        XCTAssertEqual(result.barcodeString, barcode)
        XCTAssertEqual(result.barcodeType, barcodeType)
        XCTAssertEqual(result.confidence, confidence)
        XCTAssertEqual(result.bounds, bounds)
        XCTAssertNotNil(result.timestamp)
    }
    
    func testSampleBarcodeScanResult() {
        let sampleResult = BarcodeScanResult.sample()
        
        XCTAssertEqual(sampleResult.barcodeString, "1234567890123")
        XCTAssertEqual(sampleResult.barcodeType, .ean13)
        XCTAssertEqual(sampleResult.confidence, 0.95)
        XCTAssertNotNil(sampleResult.timestamp)
    }
    
    func testCustomSampleBarcodeScanResult() {
        let customBarcode = "9876543210987"
        let sampleResult = BarcodeScanResult.sample(barcode: customBarcode)
        
        XCTAssertEqual(sampleResult.barcodeString, customBarcode)
        XCTAssertEqual(sampleResult.barcodeType, .ean13)
        XCTAssertEqual(sampleResult.confidence, 0.95)
    }
    
    func testTimestampIsRecent() {
        let result = BarcodeScanResult.sample()
        let now = Date()
        let timeDifference = abs(now.timeIntervalSince(result.timestamp))
        
        // Timestamp should be very recent (within 1 second)
        XCTAssertLessThan(timeDifference, 1.0)
    }
}

// MARK: - Permission and Authorization Tests

class BarcodeScannerAuthorizationTests: XCTestCase {
    
    var barcodeScannerService: BarcodeScannerService!
    
    override func setUp() {
        super.setUp()
        barcodeScannerService = BarcodeScannerService.mock()
    }
    
    override func tearDown() {
        barcodeScannerService = nil
        super.tearDown()
    }
    
    func testMockServiceHasAuthorizedStatus() {
        // Mock service should have authorized camera access
        XCTAssertEqual(barcodeScannerService.cameraAuthorizationStatus, .authorized)
    }
    
    func testRequestCameraPermissionReturnsPublisher() {
        let publisher = barcodeScannerService.requestCameraPermission()
        XCTAssertNotNil(publisher)
    }
    
    func testGetPreviewLayerReturnsLayer() {
        let previewLayer = barcodeScannerService.getPreviewLayer()
        XCTAssertNotNil(previewLayer)
    }
}

// MARK: - Integration Tests

class BarcodeScannerIntegrationTests: XCTestCase {
    
    func testBarcodeScannerServiceIntegrationWithCarbEntry() {
        let service = BarcodeScannerService.mock()
        let testBarcode = "7622210992338" // Example EAN-13 barcode
        
        // Simulate a barcode scan
        service.simulateScan(barcode: testBarcode)
        
        // Verify the result is available
        XCTAssertNotNil(service.lastScanResult)
        XCTAssertEqual(service.lastScanResult?.barcodeString, testBarcode)
        XCTAssertFalse(service.isScanning)
    }
    
    func testErrorHandlingFlow() {
        let service = BarcodeScannerService.mock()
        let error = BarcodeScanError.cameraPermissionDenied
        
        service.simulateError(error)
        
        XCTAssertNotNil(service.scanError)
        XCTAssertEqual(service.scanError?.localizedDescription, error.localizedDescription)
        XCTAssertFalse(service.isScanning)
    }
}