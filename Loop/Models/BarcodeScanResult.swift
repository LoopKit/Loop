//
//  BarcodeScanResult.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code for Barcode Scanning Integration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import Vision

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
#endif
