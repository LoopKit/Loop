//
//  FoodSearchBar.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code for OpenFoodFacts Integration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// A search bar component for food search with barcode scanning and AI analysis capabilities
struct FoodSearchBar: View {
    @Binding var searchText: String
    let onBarcodeScanTapped: () -> Void
    let onAICameraTapped: () -> Void
    
    @State private var showingBarcodeScanner = false
    @State private var barcodeButtonPressed = false
    @State private var aiButtonPressed = false
    @State private var aiPulseAnimation = false
    
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Expanded search field with icon
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField(
                    NSLocalizedString("Search foods...", comment: "Placeholder text for food search field"),
                    text: $searchText
                )
                .focused($isSearchFieldFocused)
                .textFieldStyle(PlainTextFieldStyle())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    // Dismiss keyboard when user hits return
                    isSearchFieldFocused = false
                }
                
                // Clear button
                if !searchText.isEmpty {
                    Button(action: {
                        // Instant haptic feedback
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        
                        withAnimation(.easeInOut(duration: 0.1)) {
                            searchText = ""
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .frame(maxWidth: .infinity) // Allow search field to expand
            
            // Right-aligned buttons group
            HStack(spacing: 12) {
                // Barcode scan button
                Button(action: {
                    print("🔍 DEBUG: Barcode button tapped")
                    print("🔍 DEBUG: showingBarcodeScanner before: \(showingBarcodeScanner)")
                    
                    // Instant haptic feedback
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    
                    // Dismiss keyboard first if active
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isSearchFieldFocused = false
                    }
                    
                    DispatchQueue.main.async {
                        showingBarcodeScanner = true
                        print("🔍 DEBUG: showingBarcodeScanner set to: \(showingBarcodeScanner)")
                    }
                    
                    onBarcodeScanTapped()
                    print("🔍 DEBUG: onBarcodeScanTapped() called")
                }) {
                    BarcodeIcon()
                        .frame(width: 60, height: 40)
                        .scaleEffect(barcodeButtonPressed ? 0.95 : 1.0)
                }
                .frame(width: 72, height: 48)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .accessibilityLabel(NSLocalizedString("Scan barcode", comment: "Accessibility label for barcode scan button"))
                .onTapGesture {
                    // Button press animation
                    withAnimation(.easeInOut(duration: 0.1)) {
                        barcodeButtonPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            barcodeButtonPressed = false
                        }
                    }
                }
                
                // AI Camera button
                Button(action: {
                    // Instant haptic feedback
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    
                    onAICameraTapped()
                }) {
                    AICameraIcon()
                        .frame(width: 42, height: 42)
                        .scaleEffect(aiButtonPressed ? 0.95 : 1.0)
                }
                .frame(width: 48, height: 48)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.purple.opacity(aiPulseAnimation ? 0.8 : 0.3), lineWidth: 2)
                        .scaleEffect(aiPulseAnimation ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: aiPulseAnimation)
                )
                .accessibilityLabel(NSLocalizedString("AI food analysis", comment: "Accessibility label for AI camera button"))
                .onTapGesture {
                    // Button press animation
                    withAnimation(.easeInOut(duration: 0.1)) {
                        aiButtonPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            aiButtonPressed = false
                        }
                    }
                }
                .onAppear {
                    // Start pulsing animation
                    aiPulseAnimation = true
                }
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingBarcodeScanner) {
            NavigationView {
                BarcodeScannerView(
                    onBarcodeScanned: { barcode in
                        print("🔍 DEBUG: FoodSearchBar received barcode: \(barcode)")
                        showingBarcodeScanner = false
                        // Barcode will be handled by CarbEntryViewModel through BarcodeScannerService publisher
                    },
                    onCancel: {
                        print("🔍 DEBUG: FoodSearchBar barcode scan cancelled")
                        showingBarcodeScanner = false
                    }
                )
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

// MARK: - Barcode Icon Component

/// Custom barcode icon that adapts to dark/light mode
struct BarcodeIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Group {
            if colorScheme == .dark {
                // Dark mode icon
                Image("icon-barcode-darkmode")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Light mode icon
                Image("icon-barcode-lightmode")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}

// MARK: - AI Camera Icon Component

/// AI camera icon for food analysis using system icon
struct AICameraIcon: View {
    var body: some View {
        Image(systemName: "sparkles")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(.purple).frame(width: 24, height: 24) // Set specific size
    }
}

// MARK: - Preview

#if DEBUG
struct FoodSearchBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            FoodSearchBar(
                searchText: .constant(""),
                onBarcodeScanTapped: {},
                onAICameraTapped: {}
            )
            
            FoodSearchBar(
                searchText: .constant("bread"),
                onBarcodeScanTapped: {},
                onAICameraTapped: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
