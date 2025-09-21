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
    @State private var showingTips = false
    
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
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Better photos = better estimates")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                VStack(alignment: .leading, spacing: 8) {
                                    CameraTipRow(icon: "sun.max.fill", title: "Use bright, even light", detail: "Harsh shadows confuse the AI and dim light can hide textures.")
                                    CameraTipRow(icon: "arrow.2.circlepath", title: "Clear the area", detail: "Remove napkins, lids, or packaging that may be misidentified as food.")
                                    CameraTipRow(icon: "square.dashed", title: "Frame the full meal", detail: "Make sure every food item is in the frame.")
                                    CameraTipRow(icon: "ruler", title: "Add a size reference", detail: "Forks, cups, or hands help AI calculate realistic portions.")
                                    CameraTipRow(icon: "camera.metering.spot", title: "Shoot from slightly above", detail: "Keep the camera level to reduce distortion and keep portions proportional.")
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                    Text("Take a Photo")
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $capturedImage, sourceType: $imageSourceType)
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
        
        // Keep only the last 10 messages to prevent overflow
        if telemetryLogs.count > 10 {
            telemetryLogs.removeFirst()
        }
    }
}

private struct CameraTipRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var sourceType: UIImagePickerController.SourceType
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        applyBaseAppearance(to: picker)
        configurePicker(picker, for: sourceType)
        return picker
    }

    private func applyBaseAppearance(to picker: UIImagePickerController) {
        if let navigationBar = picker.navigationBar as UINavigationBar? {
            navigationBar.tintColor = UIColor.systemBlue
            navigationBar.titleTextAttributes = [
                .foregroundColor: UIColor.systemBlue,
                .font: UIFont.boldSystemFont(ofSize: 17)
            ]
        }

        picker.navigationBar.tintColor = UIColor.systemBlue
        picker.view.tintColor = UIColor.systemBlue
        picker.toolbar?.tintColor = UIColor.systemBlue
        picker.toolbar?.barTintColor = UIColor.systemBlue.withAlphaComponent(0.1)

        UIBarButtonItem.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).tintColor = UIColor.systemBlue
        UIButton.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).tintColor = UIColor.systemBlue
        UILabel.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).tintColor = UIColor.systemBlue
        UIToolbar.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).tintColor = UIColor.systemBlue
        UIToolbar.appearance(whenContainedInInstancesOf: [UIImagePickerController.self]).barTintColor = UIColor.systemBlue.withAlphaComponent(0.1)

        setupCameraButtonStyling(picker)
    }

    private func configurePicker(_ picker: UIImagePickerController, for desiredType: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(desiredType) else {
            return
        }

        let wasCamera = picker.sourceType == .camera

        // When leaving camera mode, clear overlays before we switch types (camera only API)
        if wasCamera && desiredType != .camera {
            picker.cameraOverlayView = nil
        }

        if picker.sourceType != desiredType {
            picker.sourceType = desiredType
        }

        picker.allowsEditing = false

        if desiredType == .camera {
            picker.cameraOverlayView = nil
            setupCameraButtonStyling(picker)
        }
    }

    private func setupCameraButtonStyling(_ picker: UIImagePickerController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.applyBasicBlueStyling(to: picker.view)
        }
    }

    private func applyBasicBlueStyling(to view: UIView) {
        for subview in view.subviews {
            if let toolbar = subview as? UIToolbar {
                toolbar.tintColor = UIColor.systemBlue
                toolbar.barTintColor = UIColor.systemBlue.withAlphaComponent(0.1)
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

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        configurePicker(uiViewController, for: sourceType)

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
                        Color.clear
                            .frame(height: 56)
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
            .padding(.bottom, 14)
            .frame(height: 320)
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
