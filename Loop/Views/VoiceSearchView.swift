//
//  VoiceSearchView.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code for Voice Search Integration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI
import Combine

/// SwiftUI view for voice search with microphone visualization and controls
struct VoiceSearchView: View {
    @ObservedObject private var voiceService = VoiceSearchService.shared
    @Environment(\.presentationMode) var presentationMode
    
    let onSearchCompleted: (String) -> Void
    let onCancel: () -> Void
    
    @State private var showingPermissionAlert = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var audioLevelAnimation = 0.0
    
    var body: some View {
        ZStack {
                // Background
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    // Microphone visualization
                    microphoneVisualization
                    
                    // Current transcription
                    transcriptionDisplay
                    
                    // Controls
                    controlButtons
                    
                    // Error display
                    if let error = voiceService.searchError {
                        errorDisplay(error: error)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitle("Voice Search", displayMode: .inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    cancelButton
                }
            }
            .onAppear {
                setupVoiceSearch()
            }
            .onDisappear {
                voiceService.stopVoiceSearch()
            }
            .alert(isPresented: $showingPermissionAlert) {
                permissionAlert
            }
            .supportedInterfaceOrientations(.all)
    }
    
    // MARK: - Subviews
    
    private var microphoneVisualization: some View {
        ZStack {
            // Outer pulse ring
            if voiceService.isRecording {
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                    .scaleEffect(1.5 + audioLevelAnimation * 0.5)
                    .opacity(1.0 - audioLevelAnimation * 0.3)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                        value: audioLevelAnimation
                    )
            }
            
            // Main microphone button
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(voiceService.isRecording ? Color.red : Color.blue)
                        .frame(width: 120, height: 120)
                        .shadow(radius: 8)
                    
                    // Use custom icon if available, fallback to system icon
                    if let _ = UIImage(named: "icon-voice") {
                        Image("icon-voice")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                }
            }
            .scaleEffect(voiceService.isRecording ? 1.1 : 1.0)
            .animation(.spring(), value: voiceService.isRecording)
        }
        .onAppear {
            if voiceService.isRecording {
                audioLevelAnimation = 1.0
            }
        }
    }
    
    private var transcriptionDisplay: some View {
        VStack(spacing: 16) {
            if voiceService.isRecording {
                Text("Listening...")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: voiceService.isRecording)
            }
            
            if let result = voiceService.lastSearchResult {
                VStack(spacing: 8) {
                    Text("You said:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(result.transcribedText)
                        .font(.title2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    
                    if !result.isFinal {
                        Text("Processing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if !voiceService.isRecording {
                Text("Tap the microphone to start voice search")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 120)
    }
    
    private var controlButtons: some View {
        HStack(spacing: 24) {
            if voiceService.isRecording {
                // Stop button
                Button("Stop") {
                    voiceService.stopVoiceSearch()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else if let result = voiceService.lastSearchResult, result.isFinal {
                // Use result button
                Button("Search for \"\(result.transcribedText)\"") {
                    onSearchCompleted(result.transcribedText)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                // Try again button
                Button("Try Again") {
                    startVoiceSearch()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
    
    private func errorDisplay(error: VoiceSearchError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
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
                if error == .microphonePermissionDenied || error == .speechRecognitionPermissionDenied {
                    Button("Settings") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("Try Again") {
                    setupVoiceSearch()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var cancelButton: some View {
        Button("Cancel") {
            onCancel()
        }
    }
    
    private var permissionAlert: Alert {
        Alert(
            title: Text("Voice Search Permissions"),
            message: Text("Loop needs microphone and speech recognition access to perform voice searches. Please enable these permissions in Settings."),
            primaryButton: .default(Text("Settings")) {
                openSettings()
            },
            secondaryButton: .cancel()
        )
    }
    
    // MARK: - Methods
    
    private func setupVoiceSearch() {
        guard voiceService.authorizationStatus.isAuthorized else {
            requestPermissions()
            return
        }
        
        // Ready for voice search
        voiceService.searchError = nil
    }
    
    private func requestPermissions() {
        voiceService.requestPermissions()
            .sink { authorized in
                if !authorized {
                    showingPermissionAlert = true
                }
            }
            .store(in: &cancellables)
    }
    
    private func startVoiceSearch() {
        voiceService.startVoiceSearch()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Voice search failed: \(error)")
                    }
                },
                receiveValue: { result in
                    if result.isFinal {
                        // Auto-complete search after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            onSearchCompleted(result.transcribedText)
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func toggleRecording() {
        if voiceService.isRecording {
            voiceService.stopVoiceSearch()
        } else {
            startVoiceSearch()
        }
    }
    
    private func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsUrl)
    }
}

// MARK: - Preview

#if DEBUG
struct VoiceSearchView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Default state
            VoiceSearchView(
                onSearchCompleted: { text in
                    print("Search completed: \(text)")
                },
                onCancel: {
                    print("Cancelled")
                }
            )
            .previewDisplayName("Default")
            
            // Recording state
            VoiceSearchView(
                onSearchCompleted: { text in
                    print("Search completed: \(text)")
                },
                onCancel: {
                    print("Cancelled")
                }
            )
            .onAppear {
                VoiceSearchService.shared.isRecording = true
            }
            .previewDisplayName("Recording")
        }
    }
}
#endif
