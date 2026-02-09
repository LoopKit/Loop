//
//  FoodFinder_ScannerService.swift
//  Loop
//
//  FoodFinder — Barcode detection service using AVFoundation and Vision.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import AVFoundation
import Vision
import Combine
import os.log
import UIKit

/// Service for barcode scanning using the device camera and Vision framework
class BarcodeScannerService: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    /// Published scan results
    @Published var lastScanResult: BarcodeScanResult?
    
    /// Published scanning state
    @Published var isScanning: Bool = false
    
    /// Published error state
    @Published var scanError: BarcodeScanError?
    
    /// Camera authorization status
    @Published var cameraAuthorizationStatus: AVAuthorizationStatus = .notDetermined
    
    // MARK: - Scanning State Management
    
    /// Tracks recently scanned barcodes to prevent duplicates
    private var recentlyScannedBarcodes: Set<String> = []
    
    /// Timer to clear recently scanned barcodes
    private var duplicatePreventionTimer: Timer?
    
    /// Flag to prevent multiple simultaneous scan processing
    private var isProcessingScan: Bool = false
    
    /// Session health monitoring
    private var lastValidFrameTime: Date = Date()
    private var sessionHealthTimer: Timer?
    
    // Camera session components
    private let captureSession = AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "barcode.scanner.session", qos: .userInitiated)
    
    // Vision request for barcode detection
    private lazy var barcodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest(completionHandler: handleDetectedBarcodes)
        request.symbologies = [
            .ean8, .ean13, .upce, .code128, .code39, .code93,
            .dataMatrix, .qr, .pdf417, .aztec, .i2of5
        ]
        return request
    }()
    
    private let log = OSLog(category: "BarcodeScannerService")
    
    // MARK: - Public Interface
    
    /// Shared instance for app-wide use
    static let shared = BarcodeScannerService()
    
    /// Focus the camera at a specific point
    func focusAtPoint(_ point: CGPoint) {
        sessionQueue.async { [weak self] in
            self?.setFocusPoint(point)
        }
    }
    
    override init() {
        super.init()
        checkCameraAuthorization()
        setupSessionNotifications()
    }
    
    private func setupSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
    }
    
    @objc private func sessionWasInterrupted(notification: NSNotification) {
        #if DEBUG
        print("🎥 ========== Session was interrupted ==========")
        #endif
        
        if let userInfo = notification.userInfo,
           let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int,
           let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue) {
            #if DEBUG
            print("🎥 Interruption reason: \(reason)")
            #endif
            
            switch reason {
            case .videoDeviceNotAvailableInBackground:
                #if DEBUG
                print("🎥 Interruption: App went to background")
                #endif
            case .audioDeviceInUseByAnotherClient:
                #if DEBUG
                print("🎥 Interruption: Audio device in use by another client")
                #endif
            case .videoDeviceInUseByAnotherClient:
                #if DEBUG
                print("🎥 Interruption: Video device in use by another client")
                #endif
            case .videoDeviceNotAvailableWithMultipleForegroundApps:
                #if DEBUG
                print("🎥 Interruption: Video device not available with multiple foreground apps")
                #endif
            case .videoDeviceNotAvailableDueToSystemPressure:
                #if DEBUG
                print("🎥 Interruption: Video device not available due to system pressure")
                #endif
            @unknown default:
                #if DEBUG
                print("🎥 Interruption: Unknown reason")
                #endif
            }
        }
        
        DispatchQueue.main.async {
            self.isScanning = false
            // Don't immediately set an error - wait to see if interruption ends
        }
    }
    
    @objc private func sessionInterruptionEnded(notification: NSNotification) {
        #if DEBUG
        print("🎥 ========== Session interruption ended ==========")
        #endif
        
        sessionQueue.async {
            #if DEBUG
            print("🎥 Attempting to restart session after interruption...")
            #endif
            
            // Wait a bit before restarting
            Thread.sleep(forTimeInterval: 0.5)
            
            if !self.captureSession.isRunning {
                #if DEBUG
                print("🎥 Session not running, starting...")
                #endif
                self.captureSession.startRunning()
                
                // Check if it actually started
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.captureSession.isRunning {
                        #if DEBUG
                        print("🎥 ✅ Session successfully restarted after interruption")
                        #endif
                        self.isScanning = true
                        self.scanError = nil
                    } else {
                        #if DEBUG
                        print("🎥 ❌ Session failed to restart after interruption")
                        #endif
                        self.scanError = BarcodeScanError.sessionSetupFailed
                        self.isScanning = false
                    }
                }
            } else {
                #if DEBUG
                print("🎥 Session already running after interruption ended")
                #endif
                DispatchQueue.main.async {
                    self.isScanning = true
                    self.scanError = nil
                }
            }
        }
    }
    
    @objc private func sessionRuntimeError(notification: NSNotification) {
        #if DEBUG
        print("🎥 Session runtime error occurred")
        #endif
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
            #if DEBUG
            print("🎥 Runtime error: \(error.localizedDescription)")
            #endif
            
            DispatchQueue.main.async {
                self.scanError = BarcodeScanError.sessionSetupFailed
                self.isScanning = false
            }
        }
    }
    
    /// Start barcode scanning session
    func startScanning() {
        #if DEBUG
        print("🎥 ========== BarcodeScannerService.startScanning() CALLED ==========")
        #endif
        #if DEBUG
        print("🎥 Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
        #endif
        #if DEBUG
        print("🎥 Camera authorization status: \(cameraAuthorizationStatus)")
        #endif
        #if DEBUG
        print("🎥 Current session state - isRunning: \(captureSession.isRunning)")
        #endif
        #if DEBUG
        print("🎥 Current session inputs: \(captureSession.inputs.count)")
        #endif
        #if DEBUG
        print("🎥 Current session outputs: \(captureSession.outputs.count)")
        #endif
        
        // Check camera authorization fresh from the system
        let freshStatus = AVCaptureDevice.authorizationStatus(for: .video)
        #if DEBUG
        print("🎥 Fresh authorization status from system: \(freshStatus)")
        #endif
        self.cameraAuthorizationStatus = freshStatus
        
        // Ensure we have camera permission before proceeding
        guard freshStatus == .authorized else {
            #if DEBUG
            print("🎥 ERROR: Camera not authorized, status: \(freshStatus)")
            #endif
            DispatchQueue.main.async {
                if freshStatus == .notDetermined {
                    // Try to request permission
                    #if DEBUG
                    print("🎥 Permission not determined, requesting...")
                    #endif
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            if granted {
                                #if DEBUG
                                print("🎥 Permission granted, retrying scan setup...")
                                #endif
                                self.startScanning()
                            } else {
                                self.scanError = BarcodeScanError.cameraPermissionDenied
                                self.isScanning = false
                            }
                        }
                    }
                } else {
                    self.scanError = BarcodeScanError.cameraPermissionDenied
                    self.isScanning = false
                }
            }
            return
        }
        
        // Do session setup on background queue
        sessionQueue.async { [weak self] in
            guard let self = self else { 
                #if DEBUG
                print("🎥 ERROR: Self is nil in sessionQueue")
                #endif
                return 
            }
            
            #if DEBUG
            print("🎥 Setting up session on background queue...")
            #endif
            
            do {
                try self.setupCaptureSession()
                #if DEBUG
                print("🎥 Session setup completed successfully")
                #endif
                
                // Start session on background queue to avoid blocking main thread
                #if DEBUG
                print("🎥 Starting capture session...")
                #endif
                self.captureSession.startRunning()
                #if DEBUG
                print("🎥 startRunning() called, waiting for session to stabilize...")
                #endif
                
                // Wait a moment for the session to start and stabilize
                Thread.sleep(forTimeInterval: 0.3)
                
                // Check if the session is running and not interrupted
                let isRunningNow = self.captureSession.isRunning
                let isInterrupted = self.captureSession.isInterrupted
                #if DEBUG
                print("🎥 Session status after start: running=\(isRunningNow), interrupted=\(isInterrupted)")
                #endif
                
                if isRunningNow && !isInterrupted {
                    // Session started successfully
                    DispatchQueue.main.async {
                        self.isScanning = true
                        self.scanError = nil
                        #if DEBUG
                        print("🎥 ✅ SUCCESS: Session running and not interrupted")
                        #endif
                        
                        // Start session health monitoring
                        self.startSessionHealthMonitoring()
                    }
                    
                    // Monitor for delayed interruption
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if !self.captureSession.isRunning || self.captureSession.isInterrupted {
                            #if DEBUG
                            print("🎥 ⚠️ DELAYED INTERRUPTION: Session was interrupted after starting")
                            #endif
                            // Don't set error immediately - interruption handler will deal with it
                        } else {
                            #if DEBUG
                            print("🎥 ✅ Session still running after 1 second - stable")
                            #endif
                        }
                    }
                } else {
                    // Session failed to start or was immediately interrupted
                    #if DEBUG
                    print("🎥 ❌ Session failed to start properly")
                    #endif
                    DispatchQueue.main.async {
                        self.scanError = BarcodeScanError.sessionSetupFailed
                        self.isScanning = false
                    }
                }
                
                os_log("Barcode scanning session setup completed", log: self.log, type: .info)
                
            } catch let error as BarcodeScanError {
                #if DEBUG
                print("🎥 ❌ BarcodeScanError caught during setup: \(error)")
                #endif
                #if DEBUG
                print("🎥 Error description: \(error.localizedDescription)")
                #endif
                #if DEBUG
                print("🎥 Recovery suggestion: \(error.recoverySuggestion ?? "none")")
                #endif
                DispatchQueue.main.async {
                    self.scanError = error
                    self.isScanning = false
                }
            } catch {
                #if DEBUG
                print("🎥 ❌ Unknown error caught during setup: \(error)")
                #endif
                #if DEBUG
                print("🎥 Error description: \(error.localizedDescription)")
                #endif
                if let nsError = error as NSError? {
                    #if DEBUG
                    print("🎥 Error domain: \(nsError.domain)")
                    #endif
                    #if DEBUG
                    print("🎥 Error code: \(nsError.code)")
                    #endif
                    #if DEBUG
                    print("🎥 Error userInfo: \(nsError.userInfo)")
                    #endif
                }
                DispatchQueue.main.async {
                    self.scanError = BarcodeScanError.sessionSetupFailed
                    self.isScanning = false
                }
            }
        }
    }
    
    /// Stop barcode scanning session
    func stopScanning() {
        #if DEBUG
        print("🎥 stopScanning() called")
        #endif
        
        // Stop health monitoring
        stopSessionHealthMonitoring()
        
        // Clear scanning state
        DispatchQueue.main.async {
            self.isScanning = false
            self.lastScanResult = nil
            self.isProcessingScan = false
            self.recentlyScannedBarcodes.removeAll()
        }
        
        // Stop timers
        duplicatePreventionTimer?.invalidate()
        duplicatePreventionTimer = nil
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            #if DEBUG
            print("🎥 Performing complete session cleanup...")
            #endif
            
            // Stop the session if running
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                #if DEBUG
                print("🎥 Session stopped")
                #endif
            }
            
            // Wait for session to fully stop
            Thread.sleep(forTimeInterval: 0.3)
            
            // Clear all inputs and outputs to prepare for clean restart
            self.captureSession.beginConfiguration()
            
            // Remove all inputs
            for input in self.captureSession.inputs {
                #if DEBUG
                print("🎥 Removing input: \(type(of: input))")
                #endif
                self.captureSession.removeInput(input)
            }
            
            // Remove all outputs
            for output in self.captureSession.outputs {
                #if DEBUG
                print("🎥 Removing output: \(type(of: output))")
                #endif
                self.captureSession.removeOutput(output)
            }
            
            self.captureSession.commitConfiguration()
            #if DEBUG
            print("🎥 Session completely cleaned - inputs: \(self.captureSession.inputs.count), outputs: \(self.captureSession.outputs.count)")
            #endif
            
            os_log("Barcode scanning session stopped and cleaned", log: self.log, type: .info)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopScanning()
    }
    
    /// Request camera permission
    func requestCameraPermission() -> AnyPublisher<Bool, Never> {
        #if DEBUG
        print("🎥 ========== requestCameraPermission() CALLED ==========")
        #endif
        #if DEBUG
        print("🎥 Current authorization status: \(cameraAuthorizationStatus)")
        #endif
        
        return Future<Bool, Never> { [weak self] promise in
            #if DEBUG
            print("🎥 Requesting camera access...")
            #endif
            AVCaptureDevice.requestAccess(for: .video) { granted in
                #if DEBUG
                print("🎥 Camera access request result: \(granted)")
                #endif
                let newStatus = AVCaptureDevice.authorizationStatus(for: .video)
                #if DEBUG
                print("🎥 New authorization status: \(newStatus)")
                #endif
                
                DispatchQueue.main.async {
                    self?.cameraAuthorizationStatus = newStatus
                    #if DEBUG
                    print("🎥 Updated service authorization status to: \(newStatus)")
                    #endif
                    promise(.success(granted))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Clear scan state to prepare for next scan
    func clearScanState() {
        #if DEBUG
        print("🔍 Clearing scan state for next scan")
        #endif
        DispatchQueue.main.async {
            // Don't clear lastScanResult immediately - other observers may need it
            self.isProcessingScan = false
        }
        
        // Clear recently scanned after a delay to allow for a fresh scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.recentlyScannedBarcodes.removeAll()
            #if DEBUG
            print("🔍 Ready for next scan")
            #endif
        }
        
        // Clear scan result after a longer delay to allow all observers to process
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.lastScanResult = nil
            #if DEBUG
            print("🔍 Cleared lastScanResult after delay")
            #endif
        }
    }
    
    /// Complete reset of the scanner service
    func resetService() {
        #if DEBUG
        print("🎥 ========== resetService() CALLED ==========")
        #endif
        
        // Stop everything first
        stopScanning()
        
        // Wait for cleanup to complete
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Wait for session to be fully stopped and cleaned
            Thread.sleep(forTimeInterval: 0.5)
            
            DispatchQueue.main.async {
                // Reset all state
                self.lastScanResult = nil
                self.isProcessingScan = false
                self.scanError = nil
                self.recentlyScannedBarcodes.removeAll()
                
                // Reset session health monitoring
                self.lastValidFrameTime = Date()
                
                #if DEBUG
                print("🎥 ✅ Scanner service completely reset")
                #endif
            }
        }
    }
    
    /// Check if the session has existing configuration
    var hasExistingSession: Bool {
        return captureSession.inputs.count > 0 || captureSession.outputs.count > 0
    }
    
    /// Simple test function to verify basic camera access without full session setup
    func testCameraAccess() {
        #if DEBUG
        print("🎥 ========== testCameraAccess() ==========")
        #endif
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        #if DEBUG
        print("🎥 Current authorization: \(status)")
        #endif
        
        #if targetEnvironment(simulator)
        #if DEBUG
        print("🎥 Running in simulator - skipping device test")
        #endif
        return
        #endif
        
        guard status == .authorized else {
            #if DEBUG
            print("🎥 Camera not authorized - status: \(status)")
            #endif
            return
        }
        
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        
        #if DEBUG
        print("🎥 Available devices: \(devices.count)")
        #endif
        for (index, device) in devices.enumerated() {
            #if DEBUG
            print("🎥   Device \(index): \(device.localizedName) (\(device.modelID))")
            #endif
            #if DEBUG
            print("🎥     Position: \(device.position)")
            #endif
            #if DEBUG
            print("🎥     Connected: \(device.isConnected)")
            #endif
        }
        
        if let defaultDevice = AVCaptureDevice.default(for: .video) {
            #if DEBUG
            print("🎥 Default device: \(defaultDevice.localizedName)")
            #endif
            
            do {
                let input = try AVCaptureDeviceInput(device: defaultDevice)
                #if DEBUG
                print("🎥 ✅ Successfully created device input")
                #endif
                
                let testSession = AVCaptureSession()
                if testSession.canAddInput(input) {
                    #if DEBUG
                    print("🎥 ✅ Session can add input")
                    #endif
                } else {
                    #if DEBUG
                    print("🎥 ❌ Session cannot add input")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🎥 ❌ Failed to create device input: \(error)")
                #endif
            }
        } else {
            #if DEBUG
            print("🎥 ❌ No default video device available")
            #endif
        }
    }
    
    /// Setup camera session without starting scanning (for preview layer)
    func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.setupCaptureSession()
                
                DispatchQueue.main.async {
                    self.scanError = nil
                }
                
                os_log("Camera session setup completed", log: self.log, type: .info)
                
            } catch let error as BarcodeScanError {
                DispatchQueue.main.async {
                    self.scanError = error
                }
            } catch {
                DispatchQueue.main.async {
                    self.scanError = BarcodeScanError.sessionSetupFailed
                }
            }
        }
    }
    
    /// Reset and reinitialize the camera session
    func resetSession() {
        #if DEBUG
        print("🎥 ========== resetSession() CALLED ==========")
        #endif
        
        sessionQueue.async { [weak self] in
            guard let self = self else { 
                #if DEBUG
                print("🎥 ERROR: Self is nil in resetSession")
                #endif
                return 
            }
            
            #if DEBUG
            print("🎥 Performing complete session reset...")
            #endif
            
            // Stop current session
            if self.captureSession.isRunning {
                #if DEBUG
                print("🎥 Stopping running session...")
                #endif
                self.captureSession.stopRunning()
                Thread.sleep(forTimeInterval: 0.5) // Longer wait
            }
            
            // Clear all inputs and outputs
            #if DEBUG
            print("🎥 Clearing session configuration...")
            #endif
            self.captureSession.beginConfiguration()
            self.captureSession.inputs.forEach { 
                #if DEBUG
                print("🎥 Removing input: \(type(of: $0))")
                #endif
                self.captureSession.removeInput($0) 
            }
            self.captureSession.outputs.forEach { 
                #if DEBUG
                print("🎥 Removing output: \(type(of: $0))")
                #endif
                self.captureSession.removeOutput($0) 
            }
            self.captureSession.commitConfiguration()
            #if DEBUG
            print("🎥 Session cleared and committed")
            #endif
            
            // Wait longer before attempting to rebuild
            Thread.sleep(forTimeInterval: 0.5)
            
            #if DEBUG
            print("🎥 Attempting to rebuild session...")
            #endif
            do {
                try self.setupCaptureSession()
                DispatchQueue.main.async {
                    self.scanError = nil
                    #if DEBUG
                    print("🎥 ✅ Session reset successful")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🎥 ❌ Session reset failed: \(error)")
                #endif
                DispatchQueue.main.async {
                    self.scanError = BarcodeScanError.sessionSetupFailed
                }
            }
        }
    }
    
    /// Alternative simple session setup method
    func simpleSetupSession() throws {
        #if DEBUG
        print("🎥 ========== simpleSetupSession() STARTING ==========")
        #endif
        
        #if targetEnvironment(simulator)
        throw BarcodeScanError.cameraNotAvailable
        #endif
        
        guard cameraAuthorizationStatus == .authorized else {
            throw BarcodeScanError.cameraPermissionDenied
        }
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw BarcodeScanError.cameraNotAvailable
        }
        
        #if DEBUG
        print("🎥 Using device: \(device.localizedName)")
        #endif
        
        // Create a completely new session
        let newSession = AVCaptureSession()
        newSession.sessionPreset = .high
        
        // Create input
        let input = try AVCaptureDeviceInput(device: device)
        guard newSession.canAddInput(input) else {
            throw BarcodeScanError.sessionSetupFailed
        }
        
        // Create output  
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        guard newSession.canAddOutput(output) else {
            throw BarcodeScanError.sessionSetupFailed
        }
        
        // Configure session
        newSession.beginConfiguration()
        newSession.addInput(input)
        newSession.addOutput(output)
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        newSession.commitConfiguration()
        
        // Replace the old session
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        
        // This is not ideal but might be necessary
        // We'll need to use reflection or recreate the session property
        #if DEBUG
        print("🎥 Simple session setup completed")
        #endif
    }
    
    /// Get video preview layer for UI integration
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        // Always create a new preview layer to avoid conflicts
        // Each view should have its own preview layer instance
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        #if DEBUG
        print("🎥 Created preview layer for session: \(captureSession)")
        #endif
        #if DEBUG
        print("🎥 Session running: \(captureSession.isRunning), inputs: \(captureSession.inputs.count), outputs: \(captureSession.outputs.count)")
        #endif
        return previewLayer
    }
    
    // MARK: - Private Methods
    
    private func checkCameraAuthorization() {
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        #if DEBUG
        print("🎥 Camera authorization status: \(cameraAuthorizationStatus)")
        #endif
        
        #if targetEnvironment(simulator)
        #if DEBUG
        print("🎥 WARNING: Running in iOS Simulator - camera functionality will be limited")
        #endif
        #endif
        
        switch cameraAuthorizationStatus {
        case .notDetermined:
            #if DEBUG
            print("🎥 Camera permission not yet requested")
            #endif
        case .denied:
            #if DEBUG
            print("🎥 Camera permission denied by user")
            #endif
        case .restricted:
            #if DEBUG
            print("🎥 Camera access restricted by system")
            #endif
        case .authorized:
            #if DEBUG
            print("🎥 Camera permission granted")
            #endif
        @unknown default:
            #if DEBUG
            print("🎥 Unknown camera authorization status")
            #endif
        }
    }
    
    private func setupCaptureSession() throws {
        #if DEBUG
        print("🎥 ========== setupCaptureSession() STARTING ==========")
        #endif
        #if DEBUG
        print("🎥 Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
        #endif
        #if DEBUG
        print("🎥 Camera authorization status: \(cameraAuthorizationStatus)")
        #endif
        
        // Check if running in simulator
        #if targetEnvironment(simulator)
        #if DEBUG
        print("🎥 WARNING: Running in iOS Simulator - camera not available")
        #endif
        throw BarcodeScanError.cameraNotAvailable
        #endif
        
        guard cameraAuthorizationStatus == .authorized else {
            #if DEBUG
            print("🎥 ERROR: Camera permission denied - status: \(cameraAuthorizationStatus)")
            #endif
            throw BarcodeScanError.cameraPermissionDenied
        }
        
        #if DEBUG
        print("🎥 Finding best available camera device...")
        #endif
        
        // Try to get the best available camera (like AI camera does)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,      // iPhone Pro models
                .builtInDualWideCamera,    // iPhone models with dual camera
                .builtInWideAngleCamera,   // Standard camera
                .builtInUltraWideCamera    // Ultra-wide as fallback
            ],
            mediaType: .video,
            position: .back  // Prefer back camera for scanning
        )
        
        guard let videoCaptureDevice = discoverySession.devices.first else {
            #if DEBUG
            print("🎥 ERROR: No video capture device available")
            #endif
            #if DEBUG
            print("🎥 DEBUG: Available devices: \(discoverySession.devices.map { $0.modelID })")
            #endif
            throw BarcodeScanError.cameraNotAvailable
        }
        
        #if DEBUG
        print("🎥 ✅ Got video capture device: \(videoCaptureDevice.localizedName)")
        #endif
        #if DEBUG
        print("🎥 Device model: \(videoCaptureDevice.modelID)")
        #endif
        #if DEBUG
        print("🎥 Device position: \(videoCaptureDevice.position)")
        #endif
        #if DEBUG
        print("🎥 Device available: \(videoCaptureDevice.isConnected)")
        #endif
        
        // Enhanced camera configuration for optimal scanning (like AI camera)
        do {
            try videoCaptureDevice.lockForConfiguration()
            
            // Enhanced autofocus configuration
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
                #if DEBUG
                print("🎥 ✅ Enabled continuous autofocus")
                #endif
            } else if videoCaptureDevice.isFocusModeSupported(.autoFocus) {
                videoCaptureDevice.focusMode = .autoFocus
                #if DEBUG
                print("🎥 ✅ Enabled autofocus")
                #endif
            }
            
            // Set focus point to center for optimal scanning
            if videoCaptureDevice.isFocusPointOfInterestSupported {
                videoCaptureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                #if DEBUG
                print("🎥 ✅ Set autofocus point to center")
                #endif
            }
            
            // Enhanced exposure settings for better barcode/QR code detection
            if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoCaptureDevice.exposureMode = .continuousAutoExposure
                #if DEBUG
                print("🎥 ✅ Enabled continuous auto exposure")
                #endif
            } else if videoCaptureDevice.isExposureModeSupported(.autoExpose) {
                videoCaptureDevice.exposureMode = .autoExpose
                #if DEBUG
                print("🎥 ✅ Enabled auto exposure")
                #endif
            }
            
            // Set exposure point to center
            if videoCaptureDevice.isExposurePointOfInterestSupported {
                videoCaptureDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                #if DEBUG
                print("🎥 ✅ Set auto exposure point to center")
                #endif
            }
            
            // Configure for optimal performance
            if videoCaptureDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                videoCaptureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
                #if DEBUG
                print("🎥 ✅ Enabled continuous auto white balance")
                #endif
            }
            
            // Set flash to auto for low light conditions
            if videoCaptureDevice.hasFlash {
                videoCaptureDevice.flashMode = .auto
                #if DEBUG
                print("🎥 ✅ Set flash mode to auto")
                #endif
            }
            
            videoCaptureDevice.unlockForConfiguration()
            #if DEBUG
            print("🎥 ✅ Enhanced camera configuration complete")
            #endif
        } catch {
            #if DEBUG
            print("🎥 ❌ Failed to configure camera: \(error)")
            #endif
        }
        
        // Stop session if running to avoid conflicts
        if captureSession.isRunning {
            #if DEBUG
            print("🎥 Stopping existing session before reconfiguration")
            #endif
            captureSession.stopRunning()
            
            // Wait longer for the session to fully stop
            Thread.sleep(forTimeInterval: 0.3)
            #if DEBUG
            print("🎥 Session stopped, waiting completed")
            #endif
        }
        
        // Clear existing inputs and outputs
        #if DEBUG
        print("🎥 Session state before cleanup:")
        #endif
        #if DEBUG
        print("🎥   - Inputs: \(captureSession.inputs.count)")
        #endif
        #if DEBUG
        print("🎥   - Outputs: \(captureSession.outputs.count)")
        #endif
        #if DEBUG
        print("🎥   - Running: \(captureSession.isRunning)")
        #endif
        #if DEBUG
        print("🎥   - Interrupted: \(captureSession.isInterrupted)")
        #endif
        
        captureSession.beginConfiguration()
        #if DEBUG
        print("🎥 Session configuration began")
        #endif
        
        // Remove existing connections
        captureSession.inputs.forEach { 
            #if DEBUG
            print("🎥 Removing input: \(type(of: $0))")
            #endif
            captureSession.removeInput($0) 
        }
        captureSession.outputs.forEach { 
            #if DEBUG
            print("🎥 Removing output: \(type(of: $0))")
            #endif
            captureSession.removeOutput($0) 
        }
        
        do {
            #if DEBUG
            print("🎥 Creating video input from device...")
            #endif
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            #if DEBUG
            print("🎥 ✅ Created video input successfully")
            #endif
            
            // Set appropriate session preset for barcode scanning BEFORE adding inputs
            #if DEBUG
            print("🎥 Setting session preset...")
            #endif
            if captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
                #if DEBUG
                print("🎥 ✅ Set session preset to HIGH quality")
                #endif
            } else if captureSession.canSetSessionPreset(.medium) {
                captureSession.sessionPreset = .medium
                #if DEBUG
                print("🎥 ✅ Set session preset to MEDIUM quality")
                #endif
            } else {
                #if DEBUG
                print("🎥 ⚠️ Could not set preset to high or medium, using: \(captureSession.sessionPreset)")
                #endif
            }
            
            #if DEBUG
            print("🎥 Checking if session can add video input...")
            #endif
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                #if DEBUG
                print("🎥 ✅ Added video input to session successfully")
                #endif
            } else {
                #if DEBUG
                print("🎥 ❌ ERROR: Cannot add video input to session")
                #endif
                #if DEBUG
                print("🎥 Session preset: \(captureSession.sessionPreset)")
                #endif
                #if DEBUG
                print("🎥 Session interrupted: \(captureSession.isInterrupted)")
                #endif
                captureSession.commitConfiguration()
                throw BarcodeScanError.sessionSetupFailed
            }
            
            #if DEBUG
            print("🎥 Setting up video output...")
            #endif
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            
            #if DEBUG
            print("🎥 Checking if session can add video output...")
            #endif
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                
                // Set sample buffer delegate on the session queue
                videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                #if DEBUG
                print("🎥 ✅ Added video output to session successfully")
                #endif
                #if DEBUG
                print("🎥 Video output settings: \(videoOutput.videoSettings ?? [:])")
                #endif
            } else {
                #if DEBUG
                print("🎥 ❌ ERROR: Cannot add video output to session")
                #endif
                captureSession.commitConfiguration()
                throw BarcodeScanError.sessionSetupFailed
            }
            
            #if DEBUG
            print("🎥 Committing session configuration...")
            #endif
            captureSession.commitConfiguration()
            #if DEBUG
            print("🎥 ✅ Session configuration committed successfully")
            #endif
            
            #if DEBUG
            print("🎥 ========== FINAL SESSION STATE ==========")
            #endif
            #if DEBUG
            print("🎥 Inputs: \(captureSession.inputs.count)")
            #endif
            #if DEBUG
            print("🎥 Outputs: \(captureSession.outputs.count)")
            #endif
            #if DEBUG
            print("🎥 Preset: \(captureSession.sessionPreset)")
            #endif
            #if DEBUG
            print("🎥 Running: \(captureSession.isRunning)")
            #endif
            #if DEBUG
            print("🎥 Interrupted: \(captureSession.isInterrupted)")
            #endif
            #if DEBUG
            print("🎥 ========== SESSION SETUP COMPLETE ==========")
            #endif
            
        } catch let error as BarcodeScanError {
            #if DEBUG
            print("🎥 ❌ BarcodeScanError during setup: \(error)")
            #endif
            captureSession.commitConfiguration()
            throw error
        } catch {
            #if DEBUG
            print("🎥 ❌ Failed to setup capture session with error: \(error)")
            #endif
            #if DEBUG
            print("🎥 Error type: \(type(of: error))")
            #endif
            #if DEBUG
            print("🎥 Error details: \(error.localizedDescription)")
            #endif
            
            if let nsError = error as NSError? {
                #if DEBUG
                print("🎥 NSError domain: \(nsError.domain)")
                #endif
                #if DEBUG
                print("🎥 NSError code: \(nsError.code)")
                #endif
                #if DEBUG
                print("🎥 NSError userInfo: \(nsError.userInfo)")
                #endif
            }
            
            // Check for specific AVFoundation errors
            if let avError = error as? AVError {
                #if DEBUG
                print("🎥 AVError code: \(avError.code.rawValue)")
                #endif
                #if DEBUG
                print("🎥 AVError description: \(avError.localizedDescription)")
                #endif
                
                switch avError.code {
                case .deviceNotConnected:
                    #if DEBUG
                    print("🎥 SPECIFIC ERROR: Camera device not connected")
                    #endif
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.cameraNotAvailable
                case .deviceInUseByAnotherApplication:
                    #if DEBUG
                    print("🎥 SPECIFIC ERROR: Camera device in use by another application")
                    #endif
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.sessionSetupFailed
                case .deviceWasDisconnected:
                    #if DEBUG
                    print("🎥 SPECIFIC ERROR: Camera device was disconnected")
                    #endif
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.cameraNotAvailable
                case .mediaServicesWereReset:
                    #if DEBUG
                    print("🎥 SPECIFIC ERROR: Media services were reset")
                    #endif
                    captureSession.commitConfiguration()
                    throw BarcodeScanError.sessionSetupFailed
                default:
                    #if DEBUG
                    print("🎥 OTHER AVERROR: \(avError.localizedDescription)")
                    #endif
                }
            }
            
            captureSession.commitConfiguration()
            os_log("Failed to setup capture session: %{public}@", log: log, type: .error, error.localizedDescription)
            throw BarcodeScanError.sessionSetupFailed
        }
    }
    
    private func handleDetectedBarcodes(request: VNRequest, error: Error?) {
        // Update health monitoring
        lastValidFrameTime = Date()
        
        guard let observations = request.results as? [VNBarcodeObservation] else {
            if let error = error {
                os_log("Barcode detection failed: %{public}@", log: log, type: .error, error.localizedDescription)
            }
            return
        }
        
        // Prevent concurrent processing
        guard !isProcessingScan else {
            #if DEBUG
            print("🔍 Skipping barcode processing - already processing another scan")
            #endif
            return
        }
        
        // Find the best barcode detection with improved filtering
        let validBarcodes = observations.compactMap { observation -> BarcodeScanResult? in
            guard let barcodeString = observation.payloadStringValue,
                  !barcodeString.isEmpty,
                  observation.confidence > 0.5 else {  // Lower confidence for QR codes
                #if DEBUG
                print("🔍 Filtered out barcode: '\(observation.payloadStringValue ?? "nil")' confidence: \(observation.confidence)")
                #endif
                return nil
            }
            
            // Handle QR codes differently from traditional barcodes
            if observation.symbology == .qr {
                #if DEBUG
                print("🔍 QR Code detected - Raw data: '\(barcodeString.prefix(100))...'")
                #endif
                
                // For QR codes, try to extract product identifier
                let processedBarcodeString = extractProductIdentifier(from: barcodeString) ?? barcodeString
                #if DEBUG
                print("🔍 QR Code processed ID: '\(processedBarcodeString)'")
                #endif
                
                return BarcodeScanResult(
                    barcodeString: processedBarcodeString,
                    barcodeType: observation.symbology,
                    confidence: observation.confidence,
                    bounds: observation.boundingBox
                )
            } else {
                // Traditional barcode validation
                guard barcodeString.count >= 8,
                      isValidBarcodeFormat(barcodeString) else {
                    #if DEBUG
                    print("🔍 Invalid traditional barcode format: '\(barcodeString)'")
                    #endif
                    return nil
                }
                
                return BarcodeScanResult(
                    barcodeString: barcodeString,
                    barcodeType: observation.symbology,
                    confidence: observation.confidence,
                    bounds: observation.boundingBox
                )
            }
        }
        
        // Prioritize traditional barcodes over QR codes when both are present
        let bestBarcode = selectBestBarcode(from: validBarcodes)
        guard let selectedBarcode = bestBarcode else {
            return
        }
        
        // Enhanced validation - only proceed with high-confidence detections
        let minimumConfidence: Float = selectedBarcode.barcodeType == .qr ? 0.6 : 0.8
        guard selectedBarcode.confidence >= minimumConfidence else {
            #if DEBUG
            print("🔍 Barcode confidence too low: \(selectedBarcode.confidence) < \(minimumConfidence)")
            #endif
            return
        }
        
        // Ensure barcode string is valid and not empty
        guard !selectedBarcode.barcodeString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            #if DEBUG
            print("🔍 Empty or whitespace-only barcode string detected")
            #endif
            return
        }
        
        // Check for duplicates
        guard !recentlyScannedBarcodes.contains(selectedBarcode.barcodeString) else {
            #if DEBUG
            print("🔍 Skipping duplicate barcode: \(selectedBarcode.barcodeString)")
            #endif
            return
        }
        
        // Mark as processing to prevent duplicates
        isProcessingScan = true
        
        #if DEBUG
        print("🔍 ✅ Valid barcode detected: \(selectedBarcode.barcodeString) (confidence: \(selectedBarcode.confidence), minimum: \(minimumConfidence))")
        #endif
        
        // Add to recent scans to prevent duplicates
        recentlyScannedBarcodes.insert(selectedBarcode.barcodeString)
        
        // Publish result on main queue
        DispatchQueue.main.async { [weak self] in
            self?.lastScanResult = selectedBarcode
            
            // Reset processing flag after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.isProcessingScan = false
            }
            
            // Clear recently scanned after a longer delay to allow for duplicate detection
            self?.duplicatePreventionTimer?.invalidate()
            self?.duplicatePreventionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                self?.recentlyScannedBarcodes.removeAll()
                #if DEBUG
                print("🔍 Cleared recently scanned barcodes cache")
                #endif
            }
            
            os_log("Barcode detected: %{public}@ (confidence: %.2f)", 
                   log: self?.log ?? OSLog.disabled, 
                   type: .info, 
                   selectedBarcode.barcodeString, 
                   selectedBarcode.confidence)
        }
    }
    
    /// Validates barcode format to filter out false positives
    private func isValidBarcodeFormat(_ barcode: String) -> Bool {
        // Check for common barcode patterns
        let numericPattern = "^[0-9]+$"
        let alphanumericPattern = "^[A-Z0-9]+$"
        
        // EAN-13, UPC-A: 12-13 digits
        if barcode.count == 12 || barcode.count == 13 {
            return barcode.range(of: numericPattern, options: .regularExpression) != nil
        }
        
        // EAN-8, UPC-E: 8 digits
        if barcode.count == 8 {
            return barcode.range(of: numericPattern, options: .regularExpression) != nil
        }
        
        // Code 128, Code 39: Variable length alphanumeric
        if barcode.count >= 8 && barcode.count <= 40 {
            return barcode.range(of: alphanumericPattern, options: .regularExpression) != nil
        }
        
        // QR codes: Handle various data formats
        if barcode.count >= 10 {
            return isValidQRCodeData(barcode)
        }
        
        return false
    }
    
    /// Validates QR code data and extracts product identifiers if present
    private func isValidQRCodeData(_ qrData: String) -> Bool {
        // URL format QR codes (common for food products)
        if qrData.hasPrefix("http://") || qrData.hasPrefix("https://") {
            return URL(string: qrData) != nil
        }
        
        // JSON format QR codes
        if qrData.hasPrefix("{") && qrData.hasSuffix("}") {
            // Try to parse as JSON to validate structure
            if let data = qrData.data(using: .utf8),
               let _ = try? JSONSerialization.jsonObject(with: data) {
                return true
            }
        }
        
        // Product identifier formats (various standards)
        // GTIN format: (01)12345678901234
        if qrData.contains("(01)") {
            return true
        }
        
        // UPC/EAN codes within QR data
        let numericOnlyPattern = "^[0-9]+$"
        if qrData.range(of: numericOnlyPattern, options: .regularExpression) != nil {
            return qrData.count >= 8 && qrData.count <= 14
        }
        
        // Allow other structured data formats
        if qrData.count <= 500 { // Reasonable size limit for food product QR codes
            return true
        }
        
        return false
    }
    
    /// Select the best barcode from detected options, prioritizing traditional barcodes over QR codes
    private func selectBestBarcode(from barcodes: [BarcodeScanResult]) -> BarcodeScanResult? {
        guard !barcodes.isEmpty else { return nil }
        
        // Separate traditional barcodes from QR codes
        let traditionalBarcodes = barcodes.filter { result in
            result.barcodeType != .qr && result.barcodeType != .dataMatrix
        }
        let qrCodes = barcodes.filter { result in
            result.barcodeType == .qr || result.barcodeType == .dataMatrix
        }
        
        // If we have traditional barcodes, pick the one with highest confidence
        if !traditionalBarcodes.isEmpty {
            let bestTraditional = traditionalBarcodes.max { $0.confidence < $1.confidence }!
            #if DEBUG
            print("🔍 Prioritizing traditional barcode: \(bestTraditional.barcodeString) (confidence: \(bestTraditional.confidence))")
            #endif
            return bestTraditional
        }
        
        // Only use QR codes if no traditional barcodes are present
        if !qrCodes.isEmpty {
            let bestQR = qrCodes.max { $0.confidence < $1.confidence }!
            #if DEBUG
            print("🔍 Using QR code (no traditional barcode found): \(bestQR.barcodeString) (confidence: \(bestQR.confidence))")
            #endif
            
            // Check if QR code is actually food-related
            if isNonFoodQRCode(bestQR.barcodeString) {
                #if DEBUG
                print("🔍 Rejecting non-food QR code")
                #endif
                // We could show a specific error here, but for now we'll just return nil
                DispatchQueue.main.async {
                    self.scanError = BarcodeScanError.scanningFailed("This QR code is not a food product code and cannot be scanned")
                }
                return nil
            }
            
            return bestQR
        }
        
        return nil
    }
    
    /// Check if a QR code is a non-food QR code (e.g., pointing to a website)
    private func isNonFoodQRCode(_ qrData: String) -> Bool {
        // Check if it's just a URL without any product identifier
        if qrData.hasPrefix("http://") || qrData.hasPrefix("https://") {
            // If we can't extract a product identifier from the URL, it's likely non-food
            return extractProductIdentifier(from: qrData) == nil
        }
        
        // Check for common non-food QR code patterns
        let nonFoodPatterns = [
            "mailto:",
            "tel:",
            "sms:",
            "wifi:",
            "geo:",
            "contact:",
            "vcard:",
            "youtube.com",
            "instagram.com",
            "facebook.com",
            "twitter.com",
            "linkedin.com"
        ]
        
        let lowerQRData = qrData.lowercased()
        for pattern in nonFoodPatterns {
            if lowerQRData.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Extracts a usable product identifier from QR code data
    private func extractProductIdentifier(from qrData: String) -> String? {
        #if DEBUG
        print("🔍 Extracting product ID from QR data: '\(qrData.prefix(200))'")
        #endif
        
        // If it's already a simple barcode, return as-is
        let numericPattern = "^[0-9]+$"
        if qrData.range(of: numericPattern, options: .regularExpression) != nil,
           qrData.count >= 8 && qrData.count <= 14 {
            #if DEBUG
            print("🔍 Found direct numeric barcode: '\(qrData)'")
            #endif
            return qrData
        }
        
        // Extract from GTIN format: (01)12345678901234
        if qrData.contains("(01)") {
            let gtinPattern = "\\(01\\)([0-9]{12,14})"
            if let regex = try? NSRegularExpression(pattern: gtinPattern),
               let match = regex.firstMatch(in: qrData, range: NSRange(qrData.startIndex..., in: qrData)),
               let gtinRange = Range(match.range(at: 1), in: qrData) {
                let gtin = String(qrData[gtinRange])
                #if DEBUG
                print("🔍 Extracted GTIN: '\(gtin)'")
                #endif
                return gtin
            }
        }
        
        // Extract from URL path (e.g., https://example.com/product/1234567890123)
        if let url = URL(string: qrData) {
            #if DEBUG
            print("🔍 Processing URL: '\(url.absoluteString)'")
            #endif
            let pathComponents = url.pathComponents
            for component in pathComponents.reversed() {
                if component.range(of: numericPattern, options: .regularExpression) != nil,
                   component.count >= 8 && component.count <= 14 {
                    #if DEBUG
                    print("🔍 Extracted from URL path: '\(component)'")
                    #endif
                    return component
                }
            }
            
            // Check URL query parameters for product IDs
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems {
                let productIdKeys = ["id", "product_id", "gtin", "upc", "ean", "barcode"]
                for queryItem in queryItems {
                    if productIdKeys.contains(queryItem.name.lowercased()),
                       let value = queryItem.value,
                       value.range(of: numericPattern, options: .regularExpression) != nil,
                       value.count >= 8 && value.count <= 14 {
                        #if DEBUG
                        print("🔍 Extracted from URL query: '\(value)'")
                        #endif
                        return value
                    }
                }
            }
        }
        
        // Extract from JSON (look for common product ID fields)
        if qrData.hasPrefix("{") && qrData.hasSuffix("}"),
           let data = qrData.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            #if DEBUG
            print("🔍 Processing JSON QR code")
            #endif
            // Common field names for product identifiers
            let idFields = ["gtin", "upc", "ean", "barcode", "product_id", "id", "code", "productId"]
            for field in idFields {
                if let value = json[field] as? String,
                   value.range(of: numericPattern, options: .regularExpression) != nil,
                   value.count >= 8 && value.count <= 14 {
                    #if DEBUG
                    print("🔍 Extracted from JSON field '\(field)': '\(value)'")
                    #endif
                    return value
                }
                // Also check for numeric values
                if let numValue = json[field] as? NSNumber {
                    let stringValue = numValue.stringValue
                    if stringValue.count >= 8 && stringValue.count <= 14 {
                        #if DEBUG
                        print("🔍 Extracted from JSON numeric field '\(field)': '\(stringValue)'")
                        #endif
                        return stringValue
                    }
                }
            }
        }
        
        // Look for embedded barcodes in any text (more flexible extraction)
        let embeddedBarcodePattern = "([0-9]{8,14})"
        if let regex = try? NSRegularExpression(pattern: embeddedBarcodePattern),
           let match = regex.firstMatch(in: qrData, range: NSRange(qrData.startIndex..., in: qrData)),
           let barcodeRange = Range(match.range(at: 1), in: qrData) {
            let extractedBarcode = String(qrData[barcodeRange])
            #if DEBUG
            print("🔍 Found embedded barcode: '\(extractedBarcode)'")
            #endif
            return extractedBarcode
        }
        
        // If QR code is short enough, try using it directly as a product identifier
        if qrData.count <= 50 && !qrData.contains(" ") && !qrData.contains("http") {
            #if DEBUG
            print("🔍 Using short QR data directly: '\(qrData)'")
            #endif
            return qrData
        }
        
        #if DEBUG
        print("🔍 No product identifier found, returning nil")
        #endif
        return nil
    }
    
    // MARK: - Session Health Monitoring
    
    /// Set focus point for the camera
    private func setFocusPoint(_ point: CGPoint) {
        guard let device = captureSession.inputs.first as? AVCaptureDeviceInput else {
            #if DEBUG
            print("🔍 No camera device available for focus")
            #endif
            return
        }
        
        let cameraDevice = device.device
        
        do {
            try cameraDevice.lockForConfiguration()
            
            // Set focus point if supported
            if cameraDevice.isFocusPointOfInterestSupported {
                cameraDevice.focusPointOfInterest = point
                #if DEBUG
                print("🔍 Set focus point to: \(point)")
                #endif
            }
            
            // Set autofocus mode
            if cameraDevice.isFocusModeSupported(.autoFocus) {
                cameraDevice.focusMode = .autoFocus
                #if DEBUG
                print("🔍 Triggered autofocus at point: \(point)")
                #endif
            }
            
            // Set exposure point if supported
            if cameraDevice.isExposurePointOfInterestSupported {
                cameraDevice.exposurePointOfInterest = point
                #if DEBUG
                print("🔍 Set exposure point to: \(point)")
                #endif
            }
            
            // Set exposure mode
            if cameraDevice.isExposureModeSupported(.autoExpose) {
                cameraDevice.exposureMode = .autoExpose
                #if DEBUG
                print("🔍 Set auto exposure at point: \(point)")
                #endif
            }
            
            cameraDevice.unlockForConfiguration()
            
        } catch {
            #if DEBUG
            print("🔍 Error setting focus point: \(error)")
            #endif
        }
    }
    
    /// Start monitoring session health
    private func startSessionHealthMonitoring() {
        #if DEBUG
        print("🎥 Starting session health monitoring")
        #endif
        lastValidFrameTime = Date()
        
        sessionHealthTimer?.invalidate()
        sessionHealthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkSessionHealth()
        }
    }
    
    /// Stop session health monitoring
    private func stopSessionHealthMonitoring() {
        #if DEBUG
        print("🎥 Stopping session health monitoring")
        #endif
        sessionHealthTimer?.invalidate()
        sessionHealthTimer = nil
    }
    
    /// Check if the session is healthy
    private func checkSessionHealth() {
        let timeSinceLastFrame = Date().timeIntervalSince(lastValidFrameTime)
        
        #if DEBUG
        print("🎥 Health check - seconds since last frame: \(timeSinceLastFrame)")
        #endif
        
        // If no frames for more than 10 seconds, session may be stalled
        if timeSinceLastFrame > 10.0 && captureSession.isRunning && isScanning {
            #if DEBUG
            print("🎥 ⚠️ Session appears stalled - no frames for \(timeSinceLastFrame) seconds")
            #endif
            
            // Attempt to restart the session
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                
                #if DEBUG
                print("🎥 Attempting session restart due to stall...")
                #endif
                
                // Stop and restart
                self.captureSession.stopRunning()
                Thread.sleep(forTimeInterval: 0.5)
                
                if !self.captureSession.isInterrupted {
                    self.captureSession.startRunning()
                    self.lastValidFrameTime = Date()
                    #if DEBUG
                    print("🎥 Session restarted after stall")
                    #endif
                } else {
                    #if DEBUG
                    print("🎥 Cannot restart - session is interrupted")
                    #endif
                }
            }
        }
        
        // Check session state
        if !captureSession.isRunning && isScanning {
            #if DEBUG
            print("🎥 ⚠️ Session stopped but still marked as scanning")
            #endif
            DispatchQueue.main.async {
                self.isScanning = false
                self.scanError = BarcodeScanError.sessionSetupFailed
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension BarcodeScannerService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Skip processing if already processing a scan or not actively scanning
        guard isScanning && !isProcessingScan else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
            #if DEBUG
            print("🔍 Failed to get pixel buffer from sample")
            #endif
            return 
        }
        
        // Throttle processing to improve performance - process every 3rd frame
        guard arc4random_uniform(3) == 0 else { return }
        
        // Update frame time for health monitoring
        lastValidFrameTime = Date()
        
        // Determine image orientation based on device orientation
        let deviceOrientation = UIDevice.current.orientation
        let imageOrientation: CGImagePropertyOrientation
        
        switch deviceOrientation {
        case .portrait:
            imageOrientation = .right
        case .portraitUpsideDown:
            imageOrientation = .left
        case .landscapeLeft:
            imageOrientation = .up
        case .landscapeRight:
            imageOrientation = .down
        default:
            imageOrientation = .right
        }
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, 
            orientation: imageOrientation,
            options: [:]
        )
        
        do {
            try imageRequestHandler.perform([barcodeRequest])
        } catch {
            os_log("Vision request failed: %{public}@", log: log, type: .error, error.localizedDescription)
            #if DEBUG
            print("🔍 Vision request error: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Testing Support

#if DEBUG
extension BarcodeScannerService {
    /// Create a mock scanner for testing
    static func mock() -> BarcodeScannerService {
        let scanner = BarcodeScannerService()
        scanner.cameraAuthorizationStatus = .authorized
        return scanner
    }
    
    /// Simulate a successful barcode scan for testing
    func simulateScan(barcode: String) {
        let result = BarcodeScanResult.sample(barcode: barcode)
        DispatchQueue.main.async {
            self.lastScanResult = result
            self.isScanning = false
        }
    }
    
    /// Simulate a scan error for testing
    func simulateError(_ error: BarcodeScanError) {
        DispatchQueue.main.async {
            self.scanError = error
            self.isScanning = false
        }
    }
}
#endif
