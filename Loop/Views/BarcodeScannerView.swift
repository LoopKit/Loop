//
//  BarcodeScannerView.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code for Barcode Scanning Integration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import AVFoundation
import Combine

/// SwiftUI view for barcode scanning with camera preview and overlay
struct BarcodeScannerView: View {
    @ObservedObject private var scannerService = BarcodeScannerService.shared
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.dismiss) private var dismiss
    
    let onBarcodeScanned: (String) -> Void
    let onCancel: () -> Void
    
    @State private var showingPermissionAlert = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var scanningStage: ScanningStage = .initializing
    @State private var progressValue: Double = 0.0
    
    enum ScanningStage: String, CaseIterable {
        case initializing = "Initializing camera..."
        case positioning = "Position camera over barcode or QR code"
        case scanning = "Scanning for barcode or QR code..."
        case detected = "Code detected!"
        case validating = "Validating format..."
        case lookingUp = "Looking up product..."
        case found = "Product found!"
        case error = "Scan failed"
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview background
                CameraPreviewView(scanner: scannerService)
                    .edgesIgnoringSafeArea(.all)
                
                // Scanning overlay with proper safe area handling
                scanningOverlay(geometry: geometry)
                
                // Error overlay
                if let error = scannerService.scanError {
                    errorOverlay(error: error)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarTitle("Scan Barcode", displayMode: .inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    print("🎥 ========== Cancel button tapped ==========")
                    print("🎥 Stopping scanner...")
                    scannerService.stopScanning()
                    
                    print("🎥 Calling onCancel callback...")
                    onCancel()
                    
                    print("🎥 Attempting to dismiss view...")
                    // Try multiple dismiss approaches
                    DispatchQueue.main.async {
                        if #available(iOS 15.0, *) {
                            print("🎥 Using iOS 15+ dismiss()")
                            dismiss()
                        } else {
                            print("🎥 Using presentationMode dismiss()")
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    
                    print("🎥 Cancel button action complete")
                }
                .foregroundColor(.white)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button("Retry") {
                        print("🎥 Retry button tapped")
                        scannerService.resetSession()
                        setupScanner()
                    }
                    .foregroundColor(.white)
                    
                    flashlightButton
                }
            }
        }
        .onAppear {
            print("🎥 ========== BarcodeScannerView.onAppear() ==========")
            print("🎥 Current thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND")")
            
            // Clear any existing observers first to prevent duplicates
            cancellables.removeAll()
            
            // Check if we can reuse existing session or need to reset
            if scannerService.hasExistingSession && !scannerService.isScanning {
                print("🎥 Scanner has existing session but not running, attempting quick restart...")
                // Try to restart existing session first
                scannerService.startScanning()
                setupScannerAfterReset()
            } else if scannerService.hasExistingSession {
                print("🎥 Scanner has existing session and is running, performing reset...")
                scannerService.resetService()
                
                // Wait a moment for reset to complete before proceeding (reduced delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.setupScannerAfterReset()
                }
            } else {
                setupScannerAfterReset()
            }
            
            print("🎥 BarcodeScannerView onAppear setup complete")
            
            // Start scanning stage progression
            simulateScanningStages()
        }
        .onDisappear {
            scannerService.stopScanning()
        }
        .alert(isPresented: $showingPermissionAlert) {
            permissionAlert
        }
        .supportedInterfaceOrientations(.all)
    }
    
    // MARK: - Subviews
    
    private func scanningOverlay(geometry: GeometryProxy) -> some View {
        // Calculate the actual camera preview area
        let cameraPreviewArea = calculateActualCameraPreviewArea(geometry: geometry)
        
        // Position the cutout at the center of the actual camera preview
        let cutoutCenter = CGPoint(
            x: cameraPreviewArea.midX,
            y: cameraPreviewArea.midY
        )
        
        // Position the white frame with fine-tuning offset
        let finetuneOffset: CGFloat = 0 // Adjust this value to fine-tune white frame positioning
        let whiteFrameCenter = CGPoint(
            x: cameraPreviewArea.midX,
            y: cameraPreviewArea.midY - 55

            // Positive values (like +10) move the frame DOWN
            // Negative values (like -10) move the frame UP
            
        )
        
        return ZStack {
            // Full screen semi-transparent overlay with cutout
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .mask(
                    Rectangle()
                        .overlay(
                            Rectangle()
                                .frame(width: 250, height: 150)
                                .position(cutoutCenter)
                                .blendMode(.destinationOut)
                        )
                )
                .edgesIgnoringSafeArea(.all)
            
            // Progress feedback at the top
            VStack {
                ProgressiveScanFeedback(
                    stage: scanningStage,
                    progress: progressValue
                )
                .padding(.top, 20)
                
                Spacer()
            }
            
            // Scanning frame positioned at center of camera preview area
            ZStack {
                Rectangle()
                    .stroke(scanningStage == .detected ? Color.green : Color.white, lineWidth: scanningStage == .detected ? 3 : 2)
                    .frame(width: 250, height: 150)
                    .animation(.easeInOut(duration: 0.3), value: scanningStage)
                
                if scannerService.isScanning && scanningStage != .detected {
                    AnimatedScanLine()
                }
                
                if scanningStage == .detected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.green)
                        .scaleEffect(1.2)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: scanningStage)
                }
            }
            .position(whiteFrameCenter)
            
            // Instructions at the bottom
            VStack {
                Spacer()
                
                VStack(spacing: 8) {
                    Text(scanningStage.rawValue)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.2), value: scanningStage)
                    
                    if scanningStage == .positioning || scanningStage == .scanning {
                        VStack(spacing: 4) {
                            Text("Hold steady for best results")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                            
                            Text("Supports traditional barcodes and QR codes")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 60)
            }
        }
    }

    private func calculateActualCameraPreviewArea(geometry: GeometryProxy) -> CGRect {
        let screenSize = geometry.size
        let safeAreaTop = geometry.safeAreaInsets.top
        let safeAreaBottom = geometry.safeAreaInsets.bottom
        
        // Account for the top navigation area (Cancel/Retry buttons)
        let topNavigationHeight: CGFloat = 44 + safeAreaTop
        
        // Account for bottom instruction area
        let bottomInstructionHeight: CGFloat = 120 + safeAreaBottom
        
        // Available height for camera preview
        let availableHeight = screenSize.height - topNavigationHeight - bottomInstructionHeight
        let availableWidth = screenSize.width
        
        // Camera typically uses 4:3 aspect ratio
        let cameraAspectRatio: CGFloat = 4.0 / 3.0
        let availableAspectRatio = availableWidth / availableHeight
        
        let cameraRect: CGRect
        
        if availableAspectRatio > cameraAspectRatio {
            // Screen is wider than camera - camera will be letterboxed horizontally
            let cameraWidth = availableHeight * cameraAspectRatio
            let xOffset = (availableWidth - cameraWidth) / 2
            cameraRect = CGRect(
                x: xOffset,
                y: topNavigationHeight,
                width: cameraWidth,
                height: availableHeight
            )
        } else {
            // Screen is taller than camera - camera will be letterboxed vertically
            let cameraHeight = availableWidth / cameraAspectRatio
            let yOffset = topNavigationHeight + (availableHeight - cameraHeight) / 2
            cameraRect = CGRect(
                x: 0,
                y: yOffset,
                width: availableWidth,
                height: cameraHeight
            )
        }
        
        return cameraRect
    }
    
    
    private func errorOverlay(error: BarcodeScanError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text(error.localizedDescription)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 16) {
                if error == .cameraPermissionDenied {
                    Button("Settings") {
                        print("🎥 Settings button tapped")
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                VStack(spacing: 8) {
                    Button("Try Again") {
                        print("🎥 Try Again button tapped in error overlay")
                        scannerService.resetSession()
                        setupScanner()
                    }
                    
                    Button("Check Permissions") {
                        print("🎥 Check Permissions button tapped")
                        let status = AVCaptureDevice.authorizationStatus(for: .video)
                        print("🎥 Current system status: \(status)")
                        scannerService.testCameraAccess()
                        
                        // Clear the current error to test button functionality
                        scannerService.scanError = nil
                        
                        // Request permission again if needed
                        if status == .notDetermined {
                            scannerService.requestCameraPermission()
                                .sink { granted in
                                    print("🎥 Permission request result: \(granted)")
                                    if granted {
                                        setupScanner()
                                    }
                                }
                                .store(in: &cancellables)
                        } else if status != .authorized {
                            showingPermissionAlert = true
                        } else {
                            // Permission is granted, try simple setup
                            setupScanner()
                        }
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
    
    
    private var flashlightButton: some View {
        Button(action: toggleFlashlight) {
            Image(systemName: "flashlight.on.fill")
                .foregroundColor(.white)
        }
    }
    
    private var permissionAlert: Alert {
        Alert(
            title: Text("Camera Access Required"),
            message: Text("Loop needs camera access to scan barcodes. Please enable camera access in Settings."),
            primaryButton: .default(Text("Settings")) {
                openSettings()
            },
            secondaryButton: .cancel()
        )
    }
    
    // MARK: - Methods
    
    private func setupScannerAfterReset() {
        print("🎥 Setting up scanner after reset...")
        
        // Get fresh camera authorization status
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("🎥 Camera authorization from system: \(currentStatus)")
        print("🎥 Scanner service authorization: \(scannerService.cameraAuthorizationStatus)")
        
        // Update scanner service status
        scannerService.cameraAuthorizationStatus = currentStatus
        print("🎥 Updated scanner service authorization to: \(scannerService.cameraAuthorizationStatus)")
        
        // Test camera access first
        print("🎥 Running camera access test...")
        scannerService.testCameraAccess()
        
        // Start scanning immediately
        print("🎥 Calling setupScanner()...")
        setupScanner()
        
        // Listen for scan results
        print("🎥 Setting up scan result observer...")
        scannerService.$lastScanResult
            .compactMap { $0 }
            .removeDuplicates { $0.barcodeString == $1.barcodeString }  // Remove duplicate barcodes
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: false)  // Throttle rapid scans
            .sink { result in
                print("🎥 ✅ Code result received: \(result.barcodeString) (Type: \(result.barcodeType))")
                self.onBarcodeScanned(result.barcodeString)
                
                // Clear scan state immediately to prevent rapid duplicate scans
                self.scannerService.clearScanState()
                print("🔍 Cleared scan state immediately to prevent duplicates")
            }
            .store(in: &cancellables)
    }
    
    private func setupScanner() {
        print("🎥 Setting up scanner, camera status: \(scannerService.cameraAuthorizationStatus)")
        
        #if targetEnvironment(simulator)
        print("🎥 WARNING: Running in iOS Simulator - barcode scanning not supported")
        // For simulator, immediately show an error
        DispatchQueue.main.async {
            self.scannerService.scanError = BarcodeScanError.cameraNotAvailable
        }
        return
        #endif
        
        guard scannerService.cameraAuthorizationStatus != .denied else {
            print("🎥 Camera access denied, showing permission alert")
            showingPermissionAlert = true
            return
        }
        
        if scannerService.cameraAuthorizationStatus == .notDetermined {
            print("🎥 Camera permission not determined, requesting...")
            scannerService.requestCameraPermission()
                .sink { granted in
                    print("🎥 Camera permission granted: \(granted)")
                    if granted {
                        self.startScanning()
                    } else {
                        self.showingPermissionAlert = true
                    }
                }
                .store(in: &cancellables)
        } else if scannerService.cameraAuthorizationStatus == .authorized {
            print("🎥 Camera authorized, starting scanning")
            startScanning()
        }
    }
    
    private func startScanning() {
        print("🎥 BarcodeScannerView.startScanning() called")
        
        // Simply call the service method - observer already set up in onAppear
        scannerService.startScanning()
    }
    
    private func toggleFlashlight() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
        } catch {
            print("Flashlight unavailable")
        }
    }
    
    private func simulateScanningStages() {
        // Progress through scanning stages with timing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scanningStage = .positioning
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scanningStage = .scanning
            }
        }
        
        // This would be triggered by actual barcode detection
        // DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
        //     withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
        //         scanningStage = .detected
        //     }
        // }
    }
    
    private func onBarcodeDetected(_ barcode: String) {
        // Called when barcode is actually detected
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            scanningStage = .detected
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scanningStage = .validating
                progressValue = 0.3
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scanningStage = .lookingUp
                progressValue = 0.7
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scanningStage = .found
                progressValue = 1.0
            }
            
            // Call the original callback
            onBarcodeScanned(barcode)
        }
    }
    
    private func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { 
            print("🎥 ERROR: Could not create settings URL")
            return 
        }
        
        print("🎥 Opening settings URL: \(settingsUrl)")
        UIApplication.shared.open(settingsUrl) { success in
            print("🎥 Settings URL opened successfully: \(success)")
        }
    }
}

// MARK: - Camera Preview

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var scanner: BarcodeScannerService
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Only proceed if the view has valid bounds and camera is authorized
        guard uiView.bounds.width > 0 && uiView.bounds.height > 0,
              scanner.cameraAuthorizationStatus == .authorized else {
            return
        }
        
        // Check if we already have a preview layer with the same bounds
        let existingLayers = uiView.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer } ?? []
        
        // If we already have a preview layer with correct bounds, don't recreate
        if let existingLayer = existingLayers.first,
           existingLayer.frame == uiView.bounds {
            print("🎥 Preview layer already exists with correct bounds, skipping")
            return
        }
        
        // Remove any existing preview layers
        for layer in existingLayers {
            layer.removeFromSuperlayer()
        }
        
        // Create new preview layer
        if let previewLayer = scanner.getPreviewLayer() {
            previewLayer.frame = uiView.bounds
            previewLayer.videoGravity = .resizeAspectFill
            
            // Handle rotation
            if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                let orientation = UIDevice.current.orientation
                switch orientation {
                case .portrait:
                    connection.videoOrientation = .portrait
                case .portraitUpsideDown:
                    connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeRight
                case .landscapeRight:
                    connection.videoOrientation = .landscapeLeft
                default:
                    connection.videoOrientation = .portrait
                }
            }
            
            uiView.layer.insertSublayer(previewLayer, at: 0)
            print("🎥 Preview layer added to view with frame: \(previewLayer.frame)")
        }
    }
}

// MARK: - Animated Scan Line

/// Animated scanning line overlay
struct AnimatedScanLine: View {
    @State private var animationOffset: CGFloat = -75
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .green, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: animationOffset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    animationOffset = 75
                }
            }
    }
}

// MARK: - Progressive Scan Feedback Component

/// Progressive feedback panel showing scanning status and progress
struct ProgressiveScanFeedback: View {
    let stage: BarcodeScannerView.ScanningStage
    let progress: Double
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress indicator
            HStack(spacing: 8) {
                if stage == .lookingUp || stage == .validating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .fill(stageColor)
                        .frame(width: 12, height: 12)
                        .scaleEffect(stage == .detected ? 1.3 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: stage)
                }
                
                Text(stage.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            
            // Progress bar for certain stages
            if shouldShowProgress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: stageColor))
                    .frame(width: 200, height: 4)
                    .background(Color.white.opacity(0.3))
                    .cornerRadius(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .onAppear {
            simulateProgress()
        }
        .onChange(of: stage) { _ in
            simulateProgress()
        }
    }
    
    private var stageColor: Color {
        switch stage {
        case .initializing, .positioning:
            return .orange
        case .scanning:
            return .blue
        case .detected, .found:
            return .green
        case .validating, .lookingUp:
            return .yellow
        case .error:
            return .red
        }
    }
    
    private var shouldShowProgress: Bool {
        switch stage {
        case .validating, .lookingUp:
            return true
        default:
            return false
        }
    }
    
    private func simulateProgress() {
        // Simulate progress for stages that show progress bar
        if shouldShowProgress {
            withAnimation(.easeInOut(duration: 1.5)) {
                // This would be replaced with actual progress in a real implementation
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BarcodeScannerView_Previews: PreviewProvider {
    static var previews: some View {
        BarcodeScannerView(
            onBarcodeScanned: { barcode in
                print("Scanned: \(barcode)")
            },
            onCancel: {
                print("Cancelled")
            }
        )
    }
}
#endif
