//
//  FoodFinder_InputResults.swift
//  Loop
//
//  FoodFinder — Input result types for barcode scanning and voice search.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Vision
import Speech

// MARK: - Barcode Scan Result

/// Result of a barcode scanning operation
struct BarcodeScanResult {
    /// The decoded barcode string
    let barcodeString: String

    /// The type of barcode detected
    let barcodeType: VNBarcodeSymbology

    /// Confidence level of the detection (0.0 - 1.0)
    let confidence: Float

    /// Bounds of the barcode in the image
    let bounds: CGRect

    /// Timestamp when the barcode was detected
    let timestamp: Date

    init(barcodeString: String, barcodeType: VNBarcodeSymbology, confidence: Float, bounds: CGRect) {
        self.barcodeString = barcodeString
        self.barcodeType = barcodeType
        self.confidence = confidence
        self.bounds = bounds
        self.timestamp = Date()
    }
}

/// Error types for barcode scanning operations
enum BarcodeScanError: LocalizedError, Equatable {
    case cameraNotAvailable
    case cameraPermissionDenied
    case scanningFailed(String)
    case invalidBarcode
    case sessionSetupFailed

    var errorDescription: String? {
        switch self {
        case .cameraNotAvailable:
            #if targetEnvironment(simulator)
            return NSLocalizedString("Camera not available in iOS Simulator", comment: "Error message when camera is not available in simulator")
            #else
            return NSLocalizedString("Camera is not available on this device", comment: "Error message when camera is not available")
            #endif
        case .cameraPermissionDenied:
            return NSLocalizedString("Camera permission is required to scan barcodes", comment: "Error message when camera permission is denied")
        case .scanningFailed(let reason):
            return String(format: NSLocalizedString("Barcode scanning failed: %@", comment: "Error message when scanning fails"), reason)
        case .invalidBarcode:
            return NSLocalizedString("The scanned barcode is not valid", comment: "Error message when barcode is invalid")
        case .sessionSetupFailed:
            return NSLocalizedString("Camera in use by another app", comment: "Error message when camera session setup fails")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cameraNotAvailable:
            #if targetEnvironment(simulator)
            return NSLocalizedString("Use manual search or test on a physical device with a camera", comment: "Recovery suggestion when camera is not available in simulator")
            #else
            return NSLocalizedString("Use manual search or try on a device with a camera", comment: "Recovery suggestion when camera is not available")
            #endif
        case .cameraPermissionDenied:
            return NSLocalizedString("Go to Settings > Privacy & Security > Camera and enable access for Loop", comment: "Recovery suggestion when camera permission is denied")
        case .scanningFailed:
            return NSLocalizedString("Try moving the camera closer to the barcode or ensuring good lighting", comment: "Recovery suggestion when scanning fails")
        case .invalidBarcode:
            return NSLocalizedString("Try scanning a different barcode or use manual search", comment: "Recovery suggestion when barcode is invalid")
        case .sessionSetupFailed:
            return NSLocalizedString("The camera is being used by another app. Close other camera apps (Camera, FaceTime, Instagram, etc.) and tap 'Try Again'.", comment: "Recovery suggestion when session setup fails")
        }
    }
}

// MARK: - Voice Search Result

/// Result of a voice search operation
struct VoiceSearchResult {
    /// The transcribed text from speech
    let transcribedText: String

    /// Confidence level of the transcription (0.0 - 1.0)
    let confidence: Float

    /// Whether the transcription is considered final
    let isFinal: Bool

    /// Timestamp when the speech was processed
    let timestamp: Date

    /// Alternative transcription options
    let alternatives: [String]

    init(transcribedText: String, confidence: Float, isFinal: Bool, alternatives: [String] = []) {
        self.transcribedText = transcribedText
        self.confidence = confidence
        self.isFinal = isFinal
        self.alternatives = alternatives
        self.timestamp = Date()
    }
}

/// Error types for voice search operations
enum VoiceSearchError: LocalizedError, Equatable {
    case speechRecognitionNotAvailable
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case recognitionFailed(String)
    case audioSessionSetupFailed
    case recognitionTimeout
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .speechRecognitionNotAvailable:
            return NSLocalizedString("Speech recognition is not available on this device", comment: "Error message when speech recognition is not available")
        case .microphonePermissionDenied:
            return NSLocalizedString("Microphone permission is required for voice search", comment: "Error message when microphone permission is denied")
        case .speechRecognitionPermissionDenied:
            return NSLocalizedString("Speech recognition permission is required for voice search", comment: "Error message when speech recognition permission is denied")
        case .recognitionFailed(let reason):
            return String(format: NSLocalizedString("Voice recognition failed: %@", comment: "Error message when voice recognition fails"), reason)
        case .audioSessionSetupFailed:
            return NSLocalizedString("Failed to setup audio session for recording", comment: "Error message when audio session setup fails")
        case .recognitionTimeout:
            return NSLocalizedString("Voice search timed out", comment: "Error message when voice search times out")
        case .userCancelled:
            return NSLocalizedString("Voice search was cancelled", comment: "Error message when user cancels voice search")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .speechRecognitionNotAvailable:
            return NSLocalizedString("Use manual search or try on a device that supports speech recognition", comment: "Recovery suggestion when speech recognition is not available")
        case .microphonePermissionDenied:
            return NSLocalizedString("Go to Settings > Privacy & Security > Microphone and enable access for Loop", comment: "Recovery suggestion when microphone permission is denied")
        case .speechRecognitionPermissionDenied:
            return NSLocalizedString("Go to Settings > Privacy & Security > Speech Recognition and enable access for Loop", comment: "Recovery suggestion when speech recognition permission is denied")
        case .recognitionFailed, .recognitionTimeout:
            return NSLocalizedString("Try speaking more clearly or ensure you're in a quiet environment", comment: "Recovery suggestion when recognition fails")
        case .audioSessionSetupFailed:
            return NSLocalizedString("Close other audio apps and try again", comment: "Recovery suggestion when audio session setup fails")
        case .userCancelled:
            return nil
        }
    }
}

/// Voice search authorization status
enum VoiceSearchAuthorizationStatus {
    case notDetermined
    case denied
    case authorized
    case restricted

    init(speechStatus: SFSpeechRecognizerAuthorizationStatus, microphoneStatus: AVAudioSession.RecordPermission) {
        switch (speechStatus, microphoneStatus) {
        case (.authorized, .granted):
            self = .authorized
        case (.denied, _), (_, .denied):
            self = .denied
        case (.restricted, _):
            self = .restricted
        default:
            self = .notDetermined
        }
    }

    var isAuthorized: Bool {
        return self == .authorized
    }
}

// MARK: - Testing Support

#if DEBUG
extension BarcodeScanResult {
    /// Create a sample barcode scan result for testing
    static func sample(barcode: String = "1234567890123") -> BarcodeScanResult {
        return BarcodeScanResult(
            barcodeString: barcode,
            barcodeType: .ean13,
            confidence: 0.95,
            bounds: CGRect(x: 100, y: 100, width: 200, height: 50)
        )
    }
}

extension VoiceSearchResult {
    /// Create a sample voice search result for testing
    static func sample(text: String = "chicken breast") -> VoiceSearchResult {
        return VoiceSearchResult(
            transcribedText: text,
            confidence: 0.85,
            isFinal: true,
            alternatives: ["chicken breast", "chicken breasts", "chicken beast"]
        )
    }

    /// Create a partial/in-progress voice search result for testing
    static func partial(text: String = "chicken") -> VoiceSearchResult {
        return VoiceSearchResult(
            transcribedText: text,
            confidence: 0.60,
            isFinal: false,
            alternatives: ["chicken", "checkin"]
        )
    }
}
#endif
