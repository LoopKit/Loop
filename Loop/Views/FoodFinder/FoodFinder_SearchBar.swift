//
//  FoodFinder_SearchBar.swift
//  Loop
//
//  FoodFinder — Search bar with barcode scan and AI camera buttons.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - UIKit TextField (matches RowTextField pattern used by CarbQuantityRow)

/// UIKit-backed text field that properly participates in first responder handoff
/// with other UIKit text fields in the same card (e.g. CarbQuantityRow's RowTextField).
/// Dictation is detected via rapid multi-character insertion in `textChanged`.
private struct FoodSearchTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onDictationDetected: (() -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.returnKeyType = .search
        tf.font = .preferredFont(forTextStyle: .body)
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onDictationDetected: onDictationDetected)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onDictationDetected: (() -> Void)?

        init(text: Binding<String>, onDictationDetected: (() -> Void)?) {
            _text = text
            self.onDictationDetected = onDictationDetected
        }

        @objc func textChanged(_ textField: UITextField) {
            let newText = textField.text ?? ""
            let charsAdded = newText.count - text.count

            // Detect rapid multi-character insertion (dictation or paste).
            // Regular typing inserts 1 char at a time; dictation inserts entire
            // phrases at once. With autocorrection disabled, the only sources of
            // multi-char insertion are dictation and paste — both should route to AI.
            if charsAdded >= 3 && !newText.isEmpty {
                #if DEBUG
                print("🎙️ Rapid text insertion detected (\(charsAdded) chars added at once) — flagging as dictation")
                #endif
                onDictationDetected?()
            }

            text = newText
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            #if DEBUG
            print("🔍 FoodSearchTextField: DID BEGIN EDITING (keyboard should be visible)")
            #endif
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            #if DEBUG
            print("🔍 FoodSearchTextField: DID END EDITING")
            #endif
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

// MARK: - Food Search Bar

/// A search bar component for food search with barcode scanning and AI analysis capabilities
struct FoodSearchBar: View {
    @Binding var searchText: String
    let onBarcodeScanTapped: () -> Void
    let onAICameraTapped: () -> Void
    var onDictationDetected: (() -> Void)? = nil

    @State private var showingBarcodeScanner = false
    @State private var aiPulseAnimation = false

    /// Shared height so the search field and both buttons are identical
    private let rowHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            // Expanded search field with icon
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))

                FoodSearchTextField(
                    text: $searchText,
                    placeholder: NSLocalizedString("Search foods...", comment: "Placeholder text for food search field"),
                    onDictationDetected: onDictationDetected
                )
                .frame(maxWidth: .infinity)

                // Clear button
                if !searchText.isEmpty {
                    Button(action: {
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
            .frame(height: rowHeight)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .frame(maxWidth: .infinity)

            // Barcode scan button
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                DispatchQueue.main.async {
                    showingBarcodeScanner = true
                }
                onBarcodeScanTapped()
            }) {
                BarcodeIcon()
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(width: 52, height: rowHeight)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .accessibilityLabel(NSLocalizedString("Scan barcode", comment: "Accessibility label for barcode scan button"))

            // AI Camera button
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onAICameraTapped()
            }) {
                AICameraIcon()
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(width: 44, height: rowHeight)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.purple.opacity(aiPulseAnimation ? 0.8 : 0.3), lineWidth: 2)
                    .scaleEffect(aiPulseAnimation ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: aiPulseAnimation)
            )
            .accessibilityLabel(NSLocalizedString("AI food analysis", comment: "Accessibility label for AI camera button"))
            .onAppear {
                aiPulseAnimation = true
            }
        }
        .sheet(isPresented: $showingBarcodeScanner) {
            NavigationView {
                BarcodeScannerView(
                    onBarcodeScanned: { barcode in
                        showingBarcodeScanner = false
                    },
                    onCancel: {
                        showingBarcodeScanner = false
                    }
                )
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Barcode Icon Component

struct BarcodeIcon: View {
    var body: some View {
        Image(systemName: "barcode.viewfinder")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(.primary)
    }
}

// MARK: - AI Camera Icon Component

struct AICameraIcon: View {
    var body: some View {
        Image(systemName: "sparkles")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(.purple)
            .frame(width: 24, height: 24)
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
