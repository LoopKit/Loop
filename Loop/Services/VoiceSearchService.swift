//
//  VoiceSearchService.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code for Voice Search Integration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import Speech
import AVFoundation
import Combine
import os.log

/// Service for voice-to-text search functionality using Speech framework
class VoiceSearchService: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    /// Published voice search results
    @Published var lastSearchResult: VoiceSearchResult?
    
    /// Published recording state
    @Published var isRecording: Bool = false
    
    /// Published error state
    @Published var searchError: VoiceSearchError?
    
    /// Authorization status for voice search
    @Published var authorizationStatus: VoiceSearchAuthorizationStatus = .notDetermined
    
    // Speech recognition components
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Timer for recording timeout
    private var recordingTimer: Timer?
    private let maxRecordingDuration: TimeInterval = 10.0 // 10 seconds max
    
    private let log = OSLog(category: "VoiceSearchService")
    
    // Cancellables for subscription management
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Interface
    
    /// Shared instance for app-wide use
    static let shared = VoiceSearchService()
    
    override init() {
        // Initialize speech recognizer for current locale
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        
        super.init()
        
        // Check initial authorization status
        updateAuthorizationStatus()
        
        // Set speech recognizer delegate
        speechRecognizer?.delegate = self
    }
    
    /// Start voice search recording
    /// - Returns: Publisher that emits search results
    func startVoiceSearch() -> AnyPublisher<VoiceSearchResult, VoiceSearchError> {
        return Future<VoiceSearchResult, VoiceSearchError> { [weak self] promise in
            guard let self = self else { return }
            
            // Check authorization first
            self.requestPermissions()
                .sink { [weak self] authorized in
                    if authorized {
                        self?.beginRecording(promise: promise)
                    } else {
                        let error: VoiceSearchError
                        if AVAudioSession.sharedInstance().recordPermission == .denied {
                            error = .microphonePermissionDenied
                        } else {
                            error = .speechRecognitionPermissionDenied
                        }
                        
                        DispatchQueue.main.async {
                            self?.searchError = error
                        }
                        promise(.failure(error))
                    }
                }
                .store(in: &cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    /// Stop voice search recording
    func stopVoiceSearch() {
        stopRecording()
    }
    
    /// Request necessary permissions for voice search
    func requestPermissions() -> AnyPublisher<Bool, Never> {
        return Publishers.CombineLatest(
            requestSpeechRecognitionPermission(),
            requestMicrophonePermission()
        )
        .map { speechGranted, microphoneGranted in
            return speechGranted && microphoneGranted
        }
        .handleEvents(receiveOutput: { [weak self] _ in
            self?.updateAuthorizationStatus()
        })
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func updateAuthorizationStatus() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let microphoneStatus = AVAudioSession.sharedInstance().recordPermission
        authorizationStatus = VoiceSearchAuthorizationStatus(
            speechStatus: speechStatus,
            microphoneStatus: microphoneStatus
        )
    }
    
    private func requestSpeechRecognitionPermission() -> AnyPublisher<Bool, Never> {
        return Future<Bool, Never> { promise in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    promise(.success(status == .authorized))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func requestMicrophonePermission() -> AnyPublisher<Bool, Never> {
        return Future<Bool, Never> { promise in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    promise(.success(granted))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func beginRecording(promise: @escaping (Result<VoiceSearchResult, VoiceSearchError>) -> Void) {
        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Setup audio session
        do {
            try setupAudioSession()
        } catch {
            let searchError = VoiceSearchError.audioSessionSetupFailed
            DispatchQueue.main.async {
                self.searchError = searchError
            }
            promise(.failure(searchError))
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            let searchError = VoiceSearchError.recognitionFailed("Failed to create recognition request")
            DispatchQueue.main.async {
                self.searchError = searchError
            }
            promise(.failure(searchError))
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Get the input node from the audio engine
        let inputNode = audioEngine.inputNode
        
        // Create and start the recognition task
        guard let speechRecognizer = speechRecognizer else {
            let searchError = VoiceSearchError.speechRecognitionNotAvailable
            DispatchQueue.main.async {
                self.searchError = searchError
            }
            promise(.failure(searchError))
            return
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error, promise: promise)
        }
        
        // Configure the microphone input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // Start the audio engine
        do {
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isRecording = true
                self.searchError = nil
            }
            
            // Start recording timeout timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
                self?.stopRecording()
            }
            
            os_log("Voice search recording started", log: log, type: .info)
            
        } catch {
            let searchError = VoiceSearchError.audioSessionSetupFailed
            DispatchQueue.main.async {
                self.searchError = searchError
            }
            promise(.failure(searchError))
        }
    }
    
    private func setupAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func handleRecognitionResult(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        promise: @escaping (Result<VoiceSearchResult, VoiceSearchError>) -> Void
    ) {
        if let error = error {
            os_log("Speech recognition error: %{public}@", log: log, type: .error, error.localizedDescription)
            
            let searchError = VoiceSearchError.recognitionFailed(error.localizedDescription)
            DispatchQueue.main.async {
                self.searchError = searchError
                self.isRecording = false
            }
            
            stopRecording()
            return
        }
        
        guard let result = result else { return }
        
        let transcribedText = result.bestTranscription.formattedString
        let confidence = result.bestTranscription.segments.map(\.confidence).average()
        let alternatives = Array(result.transcriptions.prefix(3).map(\.formattedString))
        
        let searchResult = VoiceSearchResult(
            transcribedText: transcribedText,
            confidence: confidence,
            isFinal: result.isFinal,
            alternatives: alternatives
        )
        
        DispatchQueue.main.async {
            self.lastSearchResult = searchResult
        }
        
        os_log("Voice search result: '%{public}@' (confidence: %.2f, final: %{public}@)",
               log: log, type: .info,
               transcribedText, confidence, result.isFinal ? "YES" : "NO")
        
        // If final result or high confidence, complete the promise
        if result.isFinal || confidence > 0.8 {
            DispatchQueue.main.async {
                self.isRecording = false
            }
            stopRecording()
        }
    }
    
    private func stopRecording() {
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Stop recognition
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Cancel timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Reset audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            os_log("Failed to deactivate audio session: %{public}@", log: log, type: .error, error.localizedDescription)
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        os_log("Voice search recording stopped", log: log, type: .info)
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceSearchService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available {
                self.searchError = .speechRecognitionNotAvailable
                self.stopVoiceSearch()
            }
        }
    }
}

// MARK: - Helper Extensions

private extension Array where Element == Float {
    func average() -> Float {
        guard !isEmpty else { return 0.0 }
        return reduce(0, +) / Float(count)
    }
}

// MARK: - Testing Support

#if DEBUG
extension VoiceSearchService {
    /// Create a mock voice search service for testing
    static func mock() -> VoiceSearchService {
        let service = VoiceSearchService()
        service.authorizationStatus = .authorized
        return service
    }
    
    /// Simulate a successful voice search for testing
    func simulateVoiceSearch(text: String) {
        let result = VoiceSearchResult.sample(text: text)
        DispatchQueue.main.async {
            self.lastSearchResult = result
            self.isRecording = false
        }
    }
    
    /// Simulate a voice search error for testing
    func simulateError(_ error: VoiceSearchError) {
        DispatchQueue.main.async {
            self.searchError = error
            self.isRecording = false
        }
    }
}
#endif
