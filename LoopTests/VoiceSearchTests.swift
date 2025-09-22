//
//  VoiceSearchTests.swift
//  LoopTests
//
//  Created by Claude Code for Voice Search Testing
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import Speech
import Combine
@testable import Loop

class VoiceSearchServiceTests: XCTestCase {
    
    var voiceSearchService: VoiceSearchService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        voiceSearchService = VoiceSearchService.mock()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        voiceSearchService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testServiceInitialization() {
        XCTAssertNotNil(voiceSearchService)
        XCTAssertFalse(voiceSearchService.isRecording)
        XCTAssertNil(voiceSearchService.lastSearchResult)
        XCTAssertNil(voiceSearchService.searchError)
    }
    
    func testSharedInstanceExists() {
        let sharedInstance = VoiceSearchService.shared
        XCTAssertNotNil(sharedInstance)
    }
    
    func testMockServiceHasAuthorizedStatus() {
        XCTAssertTrue(voiceSearchService.authorizationStatus.isAuthorized)
    }
    
    // MARK: - Mock Testing
    
    func testSimulateSuccessfulVoiceSearch() {
        let expectation = XCTestExpectation(description: "Voice search result received")
        let testText = "chicken breast"
        
        voiceSearchService.$lastSearchResult
            .compactMap { $0 }
            .sink { result in
                XCTAssertEqual(result.transcribedText, testText)
                XCTAssertGreaterThan(result.confidence, 0.0)
                XCTAssertTrue(result.isFinal)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        voiceSearchService.simulateVoiceSearch(text: testText)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testSimulateVoiceSearchError() {
        let expectation = XCTestExpectation(description: "Voice search error received")
        let testError = VoiceSearchError.microphonePermissionDenied
        
        voiceSearchService.$searchError
            .compactMap { $0 }
            .sink { error in
                XCTAssertEqual(error.localizedDescription, testError.localizedDescription)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        voiceSearchService.simulateError(testError)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testRecordingStateUpdates() {
        let expectation = XCTestExpectation(description: "Recording state updated")
        
        voiceSearchService.$isRecording
            .dropFirst() // Skip initial value
            .sink { isRecording in
                XCTAssertFalse(isRecording) // Should be false after simulation
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        voiceSearchService.simulateVoiceSearch(text: "test")
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Permission Testing
    
    func testRequestPermissionsReturnsPublisher() {
        let publisher = voiceSearchService.requestPermissions()
        XCTAssertNotNil(publisher)
    }
    
    // MARK: - Error Testing
    
    func testVoiceSearchErrorTypes() {
        let errors: [VoiceSearchError] = [
            .speechRecognitionNotAvailable,
            .microphonePermissionDenied,
            .speechRecognitionPermissionDenied,
            .recognitionFailed("Test failure"),
            .audioSessionSetupFailed,
            .recognitionTimeout,
            .userCancelled
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            // Note: userCancelled doesn't have a recovery suggestion
            if error != .userCancelled {
                XCTAssertNotNil(error.recoverySuggestion)
            }
        }
    }
    
    func testErrorDescriptionsAreLocalized() {
        let error = VoiceSearchError.microphonePermissionDenied
        let description = error.errorDescription
        
        XCTAssertNotNil(description)
        XCTAssertFalse(description!.isEmpty)
        
        let suggestion = error.recoverySuggestion
        XCTAssertNotNil(suggestion)
        XCTAssertFalse(suggestion!.isEmpty)
    }
}

// MARK: - VoiceSearchResult Tests

class VoiceSearchResultTests: XCTestCase {
    
    func testVoiceSearchResultInitialization() {
        let text = "apple pie"
        let confidence: Float = 0.92
        let isFinal = true
        let alternatives = ["apple pie", "apple pies", "apple pi"]
        
        let result = VoiceSearchResult(
            transcribedText: text,
            confidence: confidence,
            isFinal: isFinal,
            alternatives: alternatives
        )
        
        XCTAssertEqual(result.transcribedText, text)
        XCTAssertEqual(result.confidence, confidence)
        XCTAssertEqual(result.isFinal, isFinal)
        XCTAssertEqual(result.alternatives, alternatives)
        XCTAssertNotNil(result.timestamp)
    }
    
    func testSampleVoiceSearchResult() {
        let sampleResult = VoiceSearchResult.sample()
        
        XCTAssertEqual(sampleResult.transcribedText, "chicken breast")
        XCTAssertEqual(sampleResult.confidence, 0.85)
        XCTAssertTrue(sampleResult.isFinal)
        XCTAssertFalse(sampleResult.alternatives.isEmpty)
        XCTAssertNotNil(sampleResult.timestamp)
    }
    
    func testCustomSampleVoiceSearchResult() {
        let customText = "salmon fillet"
        let sampleResult = VoiceSearchResult.sample(text: customText)
        
        XCTAssertEqual(sampleResult.transcribedText, customText)
        XCTAssertEqual(sampleResult.confidence, 0.85)
        XCTAssertTrue(sampleResult.isFinal)
    }
    
    func testPartialVoiceSearchResult() {
        let partialResult = VoiceSearchResult.partial()
        
        XCTAssertEqual(partialResult.transcribedText, "chicken")
        XCTAssertEqual(partialResult.confidence, 0.60)
        XCTAssertFalse(partialResult.isFinal)
        XCTAssertFalse(partialResult.alternatives.isEmpty)
    }
    
    func testCustomPartialVoiceSearchResult() {
        let customText = "bread"
        let partialResult = VoiceSearchResult.partial(text: customText)
        
        XCTAssertEqual(partialResult.transcribedText, customText)
        XCTAssertFalse(partialResult.isFinal)
    }
    
    func testTimestampIsRecent() {
        let result = VoiceSearchResult.sample()
        let now = Date()
        let timeDifference = abs(now.timeIntervalSince(result.timestamp))
        
        // Timestamp should be very recent (within 1 second)
        XCTAssertLessThan(timeDifference, 1.0)
    }
}

// MARK: - VoiceSearchAuthorizationStatus Tests

class VoiceSearchAuthorizationStatusTests: XCTestCase {
    
    func testAuthorizationStatusInit() {
        // Test authorized status
        let authorizedStatus = VoiceSearchAuthorizationStatus(
            speechStatus: .authorized,
            microphoneStatus: .granted
        )
        XCTAssertEqual(authorizedStatus, .authorized)
        XCTAssertTrue(authorizedStatus.isAuthorized)
        
        // Test denied status (speech denied)
        let deniedSpeechStatus = VoiceSearchAuthorizationStatus(
            speechStatus: .denied,
            microphoneStatus: .granted
        )
        XCTAssertEqual(deniedSpeechStatus, .denied)
        XCTAssertFalse(deniedSpeechStatus.isAuthorized)
        
        // Test denied status (microphone denied)
        let deniedMicStatus = VoiceSearchAuthorizationStatus(
            speechStatus: .authorized,
            microphoneStatus: .denied
        )
        XCTAssertEqual(deniedMicStatus, .denied)
        XCTAssertFalse(deniedMicStatus.isAuthorized)
        
        // Test restricted status
        let restrictedStatus = VoiceSearchAuthorizationStatus(
            speechStatus: .restricted,
            microphoneStatus: .granted
        )
        XCTAssertEqual(restrictedStatus, .restricted)
        XCTAssertFalse(restrictedStatus.isAuthorized)
        
        // Test not determined status
        let notDeterminedStatus = VoiceSearchAuthorizationStatus(
            speechStatus: .notDetermined,
            microphoneStatus: .undetermined
        )
        XCTAssertEqual(notDeterminedStatus, .notDetermined)
        XCTAssertFalse(notDeterminedStatus.isAuthorized)
    }
}

// MARK: - Integration Tests

class VoiceSearchIntegrationTests: XCTestCase {
    
    func testVoiceSearchServiceIntegrationWithCarbEntry() {
        let service = VoiceSearchService.mock()
        let testText = "brown rice cooked"
        
        // Simulate a voice search
        service.simulateVoiceSearch(text: testText)
        
        // Verify the result is available
        XCTAssertNotNil(service.lastSearchResult)
        XCTAssertEqual(service.lastSearchResult?.transcribedText, testText)
        XCTAssertFalse(service.isRecording)
        XCTAssertTrue(service.lastSearchResult?.isFinal ?? false)
    }
    
    func testVoiceSearchErrorHandlingFlow() {
        let service = VoiceSearchService.mock()
        let error = VoiceSearchError.speechRecognitionPermissionDenied
        
        service.simulateError(error)
        
        XCTAssertNotNil(service.searchError)
        XCTAssertEqual(service.searchError?.localizedDescription, error.localizedDescription)
        XCTAssertFalse(service.isRecording)
    }
    
    func testVoiceSearchWithAlternatives() {
        let service = VoiceSearchService.mock()
        let alternatives = ["pasta salad", "pastor salad", "pasta salads"]
        let result = VoiceSearchResult(
            transcribedText: alternatives[0],
            confidence: 0.88,
            isFinal: true,
            alternatives: alternatives
        )
        
        service.lastSearchResult = result
        
        XCTAssertEqual(service.lastSearchResult?.alternatives.count, 3)
        XCTAssertEqual(service.lastSearchResult?.alternatives.first, "pasta salad")
    }
}

// MARK: - Performance Tests

class VoiceSearchPerformanceTests: XCTestCase {
    
    func testVoiceSearchResultCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = VoiceSearchResult.sample()
            }
        }
    }
    
    func testVoiceSearchServiceInitializationPerformance() {
        measure {
            for _ in 0..<100 {
                _ = VoiceSearchService.mock()
            }
        }
    }
}