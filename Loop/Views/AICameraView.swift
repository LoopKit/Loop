//
//  AICameraView.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code for AI Food Analysis Integration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

/// Camera view for AI-powered food analysis
struct AICameraView: View {
    let onFoodAnalyzed: (AIFoodAnalysisResult, UIImage?) -> Void
    let onCancel: () -> Void
    
    @State private var capturedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var showingErrorAlert = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .camera
    @State private var telemetryLogs: [String] = []
    @State private var showTelemetry = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Auto-launch camera interface
                if capturedImage == nil {
                    VStack(spacing: 20) {
                        Spacer()
                        
                        // Simple launch message
                        VStack(spacing: 16) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 64))
                                .foregroundColor(.accentColor)
                            
                            Text("AI Food Analysis")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Camera will open to analyze your food")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        Spacer()
                        
                        // Quick action buttons  
                        VStack(spacing: 12) {
                            Button(action: {
                                imageSourceType = .camera
                                showingImagePicker = true
                            }) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14))
                                    Text("Analyze with AI")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                // Allow selecting from photo library
                                imageSourceType = .photoLibrary
                                showingImagePicker = true
                            }) {
                                HStack {
                                    Image(systemName: "photo.fill")
                                    Text("Choose from Library")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    }
                    .onAppear {
                        // Auto-launch camera when view appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            imageSourceType = .camera
                            showingImagePicker = true
                        }
                    }
                } else {
                    // Show captured image and auto-start analysis
                    VStack(spacing: 20) {
                        // Captured image
                        Image(uiImage: capturedImage!)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        
                        // Analysis in progress (auto-started)
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            
                            Text("Analyzing food with AI...")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Text("Use Cancel to retake photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Telemetry window
                            if showTelemetry && !telemetryLogs.isEmpty {
                                TelemetryWindow(logs: telemetryLogs)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .padding()
                        
                        Spacer()
                    }
                    .padding(.top)
                    .onAppear {
                        // Auto-start analysis when image appears
                        if !isAnalyzing && analysisError == nil {
                            analyzeImage()
                        }
                    }
                }
            }
            .navigationTitle("AI Food Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $capturedImage, sourceType: imageSourceType)
        }
        .alert("Analysis Error", isPresented: $showingErrorAlert) {
            // Credit/quota exhaustion errors - provide direct guidance
            if analysisError?.contains("credits exhausted") == true || analysisError?.contains("quota exceeded") == true {
                Button("Check Account") {
                    // This could open settings or provider website in future enhancement
                    analysisError = nil
                }
                Button("Try Different Provider") {
                    ConfigurableAIService.shared.resetToDefault()
                    analysisError = nil
                    analyzeImage()
                }
                Button("Retake Photo") {
                    capturedImage = nil
                    analysisError = nil
                }
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                }
            }
            // Rate limit errors - suggest waiting
            else if analysisError?.contains("rate limit") == true {
                Button("Wait and Retry") {
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                        analyzeImage()
                    }
                }
                Button("Try Different Provider") {
                    ConfigurableAIService.shared.resetToDefault()
                    analysisError = nil
                    analyzeImage()
                }
                Button("Retake Photo") {
                    capturedImage = nil
                    analysisError = nil
                }
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                }
            }
            // General errors - provide standard options
            else {
                Button("Retry Analysis") {
                    analyzeImage()
                }
                Button("Retake Photo") {
                    capturedImage = nil
                    analysisError = nil
                }
                if analysisError?.contains("404") == true || analysisError?.contains("service error") == true {
                    Button("Reset to Default") {
                        ConfigurableAIService.shared.resetToDefault()
                        analysisError = nil
                        analyzeImage()
                    }
                }
                Button("Cancel", role: .cancel) {
                    analysisError = nil
                }
            }
        } message: {
            if analysisError?.contains("credits exhausted") == true {
                Text("Your AI provider has run out of credits. Please check your account billing or try a different provider.")
            } else if analysisError?.contains("quota exceeded") == true {
                Text("Your AI provider quota has been exceeded. Please check your usage limits or try a different provider.")
            } else if analysisError?.contains("rate limit") == true {
                Text("Too many requests sent to your AI provider. Please wait a moment before trying again.")
            } else {
                Text(analysisError ?? "Unknown error occurred")
            }
        }
    }
    
    private func analyzeImage() {
        guard let image = capturedImage else { return }
        
        // Check if AI service is configured
        let aiService = ConfigurableAIService.shared
        guard aiService.isConfigured else {
            analysisError = "AI service not configured. Please check settings."
            showingErrorAlert = true
            return
        }
        
        isAnalyzing = true
        analysisError = nil
        telemetryLogs = []
        showTelemetry = true
        
        // Start telemetry logging with progressive steps
        addTelemetryLog("🔍 Initializing AI food analysis...")
        
        Task {
            do {
                // Step 1: Image preparation
                await MainActor.run {
                    addTelemetryLog("📱 Processing image data...")
                }
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                await MainActor.run {
                    addTelemetryLog("💼 Optimizing image quality...")
                }
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                // Step 2: AI connection
                await MainActor.run {
                    addTelemetryLog("🧠 Connecting to AI provider...")
                }
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                await MainActor.run {
                    addTelemetryLog("📡 Uploading image for analysis...")
                }
                try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
                
                // Step 3: Analysis stages
                await MainActor.run {
                    addTelemetryLog("📊 Analyzing nutritional content...")
                }
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                await MainActor.run {
                    addTelemetryLog("🔬 Identifying food portions...")
                }
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                await MainActor.run {
                    addTelemetryLog("📏 Calculating serving sizes...")
                }
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                await MainActor.run {
                    addTelemetryLog("⚖️ Comparing to USDA standards...")
                }
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                // Step 4: AI processing (actual call)
                await MainActor.run {
                    addTelemetryLog("🤖 Running AI vision analysis...")
                }
                
                let result = try await aiService.analyzeFoodImage(image) { telemetryMessage in
                    Task { @MainActor in
                        addTelemetryLog(telemetryMessage)
                    }
                }
                
                // Step 5: Results processing
                await MainActor.run {
                    addTelemetryLog("📊 Processing analysis results...")
                }
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                await MainActor.run {
                    addTelemetryLog("🍽️ Generating nutrition summary...")
                }
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                await MainActor.run {
                    addTelemetryLog("✅ Analysis complete!")
                    
                    // Hide telemetry after a brief moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showTelemetry = false
                        isAnalyzing = false
                        onFoodAnalyzed(result, capturedImage)
                    }
                }
            } catch {
                await MainActor.run {
                    addTelemetryLog("⚠️ Connection interrupted...")
                }
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                await MainActor.run {
                    addTelemetryLog("❌ Analysis failed")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showTelemetry = false
                        isAnalyzing = false
                        analysisError = error.localizedDescription
                        showingErrorAlert = true
                    }
                }
            }
        }
    }
    
    private func addTelemetryLog(_ message: String) {
        telemetryLogs.append(message)
        
        // Keep only the last 5 messages to prevent overflow
        if telemetryLogs.count > 5 {
            telemetryLogs.removeFirst()
        }
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = sourceType == .camera // Only enable editing for camera, not photo library
        
        // Style the navigation bar and buttons to be blue with AI branding
        if let navigationBar = picker.navigationBar as UINavigationBar? {
            navigationBar.tintColor = UIColor.systemBlue
            navigationBar.titleTextAttributes = [
                .foregroundColor: UIColor.systemBlue,
                .font: UIFont.boldSystemFont(ofSize: 17)
            ]
        }
        
        // Apply comprehensive UI styling for AI branding
        picker.navigationBar.tintColor = UIColor.systemBlue
        
        // Style all buttons in the camera interface to be blue with appearance proxies
        UIBarButtonItem.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).tintColor = UIColor.systemBlue
        UIButton.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).tintColor = UIColor.systemBlue
        UILabel.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).tintColor = UIColor.systemBlue
        
        // Style toolbar buttons (including "Use Photo" button)
        picker.toolbar?.tintColor = UIColor.systemBlue
        UIToolbar.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).tintColor = UIColor.systemBlue
        UIToolbar.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).barTintColor = UIColor.systemBlue.withAlphaComponent(0.1)
        
        // Apply blue styling to all UI elements in camera
        picker.view.tintColor = UIColor.systemBlue
        
        // Set up custom button styling with multiple attempts
        setupCameraButtonStyling(picker)
        
        // Add combined camera overlay for AI analysis and tips
        if sourceType == .camera {
            picker.cameraFlashMode = .auto
            addCombinedCameraOverlay(to: picker)
        }
        
        return picker
    }
    
    private func addCombinedCameraOverlay(to picker: UIImagePickerController) {
        // Create main overlay view
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.clear
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create photo tips container (positioned at bottom to avoid viewfinder interference)
        let tipsContainer = UIView()
        tipsContainer.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        tipsContainer.layer.cornerRadius = 12
        tipsContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Create tips text (simplified to prevent taking too much space)
        let tipsLabel = UILabel()
        tipsLabel.text = "📸 Tips: Take overhead photos • Include size reference • Good lighting"
        tipsLabel.textColor = UIColor.white
        tipsLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        tipsLabel.numberOfLines = 2
        tipsLabel.textAlignment = .center
        tipsLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add views to overlay
        overlayView.addSubview(tipsContainer)
        tipsContainer.addSubview(tipsLabel)
        
        // Set up constraints - position tips at bottom to avoid interfering with viewfinder
        NSLayoutConstraint.activate([
            // Tips container at bottom, above the camera controls
            tipsContainer.bottomAnchor.constraint(equalTo: overlayView.safeAreaLayoutGuide.bottomAnchor, constant: -120),
            tipsContainer.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 20),
            tipsContainer.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -20),
            
            // Tips label within container
            tipsLabel.topAnchor.constraint(equalTo: tipsContainer.topAnchor, constant: 8),
            tipsLabel.leadingAnchor.constraint(equalTo: tipsContainer.leadingAnchor, constant: 12),
            tipsLabel.trailingAnchor.constraint(equalTo: tipsContainer.trailingAnchor, constant: -12),
            tipsLabel.bottomAnchor.constraint(equalTo: tipsContainer.bottomAnchor, constant: -8)
        ])
        
        // Set overlay as camera overlay
        picker.cameraOverlayView = overlayView
    }
    
    private func setupCameraButtonStyling(_ picker: UIImagePickerController) {
        // Apply basic blue theme to navigation elements only
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.applyBasicBlueStyling(to: picker.view)
        }
    }
    
    private func applyBasicBlueStyling(to view: UIView) {
        // Apply only basic blue theme to navigation elements
        for subview in view.subviews {
            if let toolbar = subview as? UIToolbar {
                toolbar.tintColor = UIColor.systemBlue
                toolbar.barTintColor = UIColor.systemBlue.withAlphaComponent(0.1)
                
                // Style toolbar items but don't modify text
                toolbar.items?.forEach { item in
                    item.tintColor = UIColor.systemBlue
                }
            }
            
            if let navBar = subview as? UINavigationBar {
                navBar.tintColor = UIColor.systemBlue
                navBar.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
            }
            
            applyBasicBlueStyling(to: subview)
        }
    }
    
    // Button styling methods removed - keeping native Use Photo button as-is
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Apply basic styling only
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.applyBasicBlueStyling(to: uiViewController.view)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Use edited image if available, otherwise fall back to original
            if let uiImage = info[.editedImage] as? UIImage {
                parent.image = uiImage
            } else if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Telemetry Window

struct TelemetryWindow: View {
    let logs: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.green)
                    .font(.caption2)
                Text("Analysis Status")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            
            // Scrolling logs
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                            HStack {
                                Text(log)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .id(index)
                        }
                        
                        // Add bottom padding to prevent cutoff
                        Spacer(minLength: 24)
                    }
                    .onAppear {
                        // Auto-scroll to latest log
                        if !logs.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: logs.count) { _ in
                        // Auto-scroll to latest log when new ones are added
                        if !logs.isEmpty {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(height: 210)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .padding(.top, 8)
    }
}

// MARK: - Preview

#if DEBUG
struct AICameraView_Previews: PreviewProvider {
    static var previews: some View {
        AICameraView(
            onFoodAnalyzed: { result, image in
                print("Food analyzed: \(result)")
            },
            onCancel: {
                print("Cancelled")
            }
        )
    }
}

struct TelemetryWindow_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TelemetryWindow(logs: [
                "🔍 Initializing AI food analysis...",
                "📱 Processing image data...",
                "🧠 Connecting to AI provider...",
                "📊 Analyzing nutritional content...",
                "✅ Analysis complete!"
            ])
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
#endif
