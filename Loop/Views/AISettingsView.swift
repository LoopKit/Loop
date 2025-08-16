//
//  AISettingsView.swift
//  Loop
//
//  Created by Taylor Patterson, Coded by Claude Code for AI Settings Configuration in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Simple secure field that uses proper SwiftUI components
struct StableSecureField: View {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    
    var body: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .autocorrectionDisabled()
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .autocorrectionDisabled()
        }
    }
}

/// Settings view for configuring AI food analysis
struct AISettingsView: View {
    @ObservedObject private var aiService = ConfigurableAIService.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var claudeKey: String = ""
    @State private var claudeQuery: String = ""
    @State private var openAIKey: String = ""
    @State private var openAIQuery: String = ""
    @State private var googleGeminiKey: String = ""
    @State private var googleGeminiQuery: String = ""
    @State private var showingAPIKeyAlert = false
    
    // API Key visibility toggles - start with keys hidden (secure)
    @State private var showClaudeKey: Bool = false
    @State private var showOpenAIKey: Bool = false
    @State private var showGoogleGeminiKey: Bool = false
    
    // Feature flag for Food Search
    @State private var foodSearchEnabled: Bool = UserDefaults.standard.foodSearchEnabled
    
    // Feature flag for Advanced Dosing Recommendations
    @State private var advancedDosingRecommendationsEnabled: Bool = UserDefaults.standard.advancedDosingRecommendationsEnabled
    
    // GPT-5 feature flag
    @State private var useGPT5ForOpenAI: Bool = UserDefaults.standard.useGPT5ForOpenAI
    
    init() {
        _claudeKey = State(initialValue: ConfigurableAIService.shared.getAPIKey(for: .claude) ?? "")
        _claudeQuery = State(initialValue: ConfigurableAIService.shared.getQuery(for: .claude) ?? "")
        _openAIKey = State(initialValue: ConfigurableAIService.shared.getAPIKey(for: .openAI) ?? "")
        _openAIQuery = State(initialValue: ConfigurableAIService.shared.getQuery(for: .openAI) ?? "")
        _googleGeminiKey = State(initialValue: ConfigurableAIService.shared.getAPIKey(for: .googleGemini) ?? "")
        _googleGeminiQuery = State(initialValue: ConfigurableAIService.shared.getQuery(for: .googleGemini) ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Feature Toggle Section
                Section(header: Text("Food Search Feature"), 
                       footer: Text("Enable this to show Food Search functionality in the carb entry screen. When disabled, the feature is hidden but all your settings are preserved.")) {
                    Toggle("Enable Food Search", isOn: $foodSearchEnabled)
                }
                
                // Advanced Dosing Recommendations Section
                Section(header: Text("Advanced Dosing Recommendations"), 
                       footer: Text("Enable advanced dosing advice including Fat/Protein Units (FPUs) calculations, extended bolus timing, excersize impact, and absorption time estimates. FPUs help account for the delayed glucose impact from fat and protein in meals, which can affect blood sugar 3-8 hours after eating.")) {
                    Toggle("Advanced Dosing Recommendations", isOn: $advancedDosingRecommendationsEnabled)
                        .disabled(!foodSearchEnabled)
                }
                
                // GPT-5 Feature Section - Only show when OpenAI is selected for AI Image Analysis
                if aiService.aiImageSearchProvider.rawValue.contains("OpenAI") {
                    Section(header: Text("OpenAI GPT-5 (Latest)"), 
                           footer: Text("Enable GPT-5, GPT-5-mini, and GPT-5-nano models for OpenAI analysis. Standard Quality uses GPT-5, Fast Mode uses GPT-5-nano for ultra-fast analysis. GPT-5 takes longer to perform analysis but these are the latest models with some improvements in health advisory accuracy. Fallback to GPT-4o if unavailable.")) {
                        Toggle("Use GPT-5 Models", isOn: $useGPT5ForOpenAI)
                            .disabled(!foodSearchEnabled)
                            .onChange(of: useGPT5ForOpenAI) { _ in
                                // Trigger view refresh to update Analysis Mode descriptions
                                aiService.objectWillChange.send()
                            }
                    }
                }
                
                // Only show configuration sections if feature is enabled
                if foodSearchEnabled {
                    Section(header: Text("Food Search Provider Configuration"), 
                       footer: Text("Configure the API service used for each type of food search. AI Image Analysis controls what happens when you take photos of food. Different providers excel at different search methods.")) {
                    
                    ForEach(SearchType.allCases, id: \.self) { searchType in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(searchType.rawValue)
                                    .font(.headline)
                                Spacer()
                            }
                            
                            Text(searchType.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Provider for \(searchType.rawValue)", selection: getBindingForSearchType(searchType)) {
                                ForEach(aiService.getAvailableProvidersForSearchType(searchType), id: \.self) { provider in
                                    Text(provider.rawValue).tag(provider)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Analysis Mode Configuration
                Section(header: Text("AI Analysis Mode"), 
                       footer: Text("Choose between speed and accuracy. Fast mode uses lighter AI models for 2-3x faster analysis with slightly reduced accuracy (~5-10% trade-off). Standard mode uses full AI models for maximum accuracy.")) {
                    
                    analysisModeSection
                }
                
                // Claude API Configuration
                Section(header: Text("Anthropic (Claude API) Configuration"), 
                       footer: Text("Get a Claude API key from console.anthropic.com. Claude excels at detailed reasoning and food analysis. Pricing starts at $0.25 per million tokens for Haiku model.")) {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Claude API Key")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    showClaudeKey.toggle()
                                }) {
                                    Image(systemName: showClaudeKey ? "eye.slash" : "eye")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            HStack {
                                StableSecureField(
                                    placeholder: "Enter your Claude API key",
                                    text: $claudeKey,
                                    isSecure: !showClaudeKey
                                )
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("AI Prompt for Enhanced Results")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Menu("Examples") {
                                    Button("Default Query") {
                                        claudeQuery = "Analyze this food image for diabetes management. Describe exactly what you see in detail: colors, textures, cooking methods, plate type, utensils, and food arrangement. Identify each food item with specific preparation details, estimate precise portion sizes using visual references, and provide carbohydrates, protein, fat, and calories for each component. Focus on accurate carbohydrate estimation for insulin dosing."
                                    }
                                    
                                    Button("Detailed Visual Analysis") {
                                        claudeQuery = "Provide extremely detailed visual analysis of this food image. Describe every element you can see: food colors, textures, cooking methods (grilled marks, browning, steaming), plate type and size, utensils present, garnishes, sauces, cooking oils visible, food arrangement, and background elements. Use these visual details to estimate precise portion sizes and calculate accurate nutrition values for diabetes management."
                                    }
                                    
                                    Button("Diabetes Focus") {
                                        claudeQuery = "Focus specifically on carbohydrate analysis for Type 1 diabetes management. Identify all carb sources, estimate absorption timing, and provide detailed carb counts with confidence levels."
                                    }
                                    
                                    Button("Macro Tracking") {
                                        claudeQuery = "Provide complete macronutrient analysis with detailed portion reasoning. For each food component, describe the visual cues you're using for portion estimation: compare to visible objects (fork, plate, hand), note cooking methods affecting nutrition (oils, preparation style), explain food quality indicators (ripeness, doneness), and provide comprehensive nutrition breakdown with your confidence level for each estimate."
                                    }
                                }
                                .font(.caption)
                            }
                            
                            TextEditor(text: $claudeQuery)
                                .frame(minHeight: 80)
                                .border(Color.secondary.opacity(0.3), width: 0.5)
                        }
                    }
                }
                
                // Google Gemini API Configuration
                Section(header: Text("Google (Gemini API) Configuration"), 
                       footer: Text("Get a free API key from ai.google.dev. Google Gemini provides excellent food recognition with generous free tier (1500 requests per day).")) {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Google Gemini API Key")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    showGoogleGeminiKey.toggle()
                                }) {
                                    Image(systemName: showGoogleGeminiKey ? "eye.slash" : "eye")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            HStack {
                                StableSecureField(
                                    placeholder: "Enter your Google Gemini API key",
                                    text: $googleGeminiKey,
                                    isSecure: !showGoogleGeminiKey
                                )
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("AI Prompt for Enhanced Results")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Menu("Examples") {
                                    Button("Default Query") {
                                        googleGeminiQuery = "Analyze this food image for diabetes management. Describe exactly what you see in detail: colors, textures, cooking methods, plate type, utensils, and food arrangement. Identify each food item with specific preparation details, estimate precise portion sizes using visual references, and provide carbohydrates, protein, fat, and calories for each component. Focus on accurate carbohydrate estimation for insulin dosing."
                                    }
                                    
                                    Button("Detailed Visual Analysis") {
                                        googleGeminiQuery = "Provide extremely detailed visual analysis of this food image. Describe every element you can see: food colors, textures, cooking methods (grilled marks, browning, steaming), plate type and size, utensils present, garnishes, sauces, cooking oils visible, food arrangement, and background elements. Use these visual details to estimate precise portion sizes and calculate accurate nutrition values for diabetes management."
                                    }
                                    
                                    Button("Diabetes Focus") {
                                        googleGeminiQuery = "Identify all food items in this image with focus on carbohydrate content for diabetes management. Provide detailed carb counts for each component and total meal carbohydrates."
                                    }
                                    
                                    Button("Macro Tracking") {
                                        googleGeminiQuery = "Break down this meal into individual components with complete macronutrient profiles (carbs, protein, fat, calories) per item and combined totals."
                                    }
                                }
                                .font(.caption)
                            }
                            
                            TextEditor(text: $googleGeminiQuery)
                                .frame(minHeight: 80)
                                .border(Color.secondary.opacity(0.3), width: 0.5)
                        }
                    }
                }
                
                // OpenAI (ChatGPT) API Configuration
                Section(header: Text("OpenAI (ChatGPT API) Configuration"), 
                       footer: Text("Get an API key from platform.openai.com. Customize the analysis prompt to get specific meal component breakdowns and nutrition totals. (~$0.01 per image)")) {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("ChatGPT (OpenAI) API Key")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    showOpenAIKey.toggle()
                                }) {
                                    Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            HStack {
                                StableSecureField(
                                    placeholder: "Enter your OpenAI API key",
                                    text: $openAIKey,
                                    isSecure: !showOpenAIKey
                                )
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("AI Prompt for Enhanced Results")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Menu("Examples") {
                                    Button("Default Query") {
                                        openAIQuery = "Analyze this food image for diabetes management. Describe exactly what you see in detail: colors, textures, cooking methods, plate type, utensils, and food arrangement. Identify each food item with specific preparation details, estimate precise portion sizes using visual references, and provide carbohydrates, protein, fat, and calories for each component. Focus on accurate carbohydrate estimation for insulin dosing."
                                    }
                                    
                                    Button("Detailed Visual Analysis") {
                                        openAIQuery = "Provide extremely detailed visual analysis of this food image. Describe every element you can see: food colors, textures, cooking methods (grilled marks, browning, steaming), plate type and size, utensils present, garnishes, sauces, cooking oils visible, food arrangement, and background elements. Use these visual details to estimate precise portion sizes and calculate accurate nutrition values for diabetes management."
                                    }
                                    
                                    Button("Diabetes Focus") {
                                        openAIQuery = "Identify all food items in this image with focus on carbohydrate content for diabetes management. Provide detailed carb counts for each component and total meal carbohydrates."
                                    }
                                    
                                    Button("Macro Tracking") {
                                        openAIQuery = "Break down this meal into individual components with complete macronutrient profiles (carbs, protein, fat, calories) per item and combined totals."
                                    }
                                }
                                .font(.caption)
                            }
                            
                            TextEditor(text: $openAIQuery)
                                .frame(minHeight: 80)
                                .border(Color.secondary.opacity(0.3), width: 0.5)
                        }
                    }
                }
                
                Section(header: Text("Important: How to Use Your API Keys"), 
                       footer: Text("To use your paid API keys, make sure to select the corresponding provider in 'AI Image Analysis' above. The provider you select for AI Image Analysis is what will be used when you take photos of food.")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundColor(.blue)
                            Text("Camera Food Analysis")
                                .font(.headline)
                        }
                        
                        Text("When you take a photo of food, the app uses the provider selected in 'AI Image Analysis' above.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("✅ Select 'Anthropic (Claude API)', 'Google (Gemini API)', or 'OpenAI (ChatGPT API)' for AI Image Analysis to use your paid keys")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Text("❌ If you select 'OpenFoodFacts' or 'USDA', camera analysis will use basic estimation instead of AI")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Section(header: Text("Provider Information")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Search Providers:")
                            .font(.headline)
                        
                        Text("• **Anthropic (Claude API)**: Advanced AI with detailed reasoning. Excellent at food analysis and portion estimation. Requires API key (~$0.25 per million tokens).")
                        
                        Text("• **Google (Gemini API)**: Free AI with generous limits (1500/day). Excellent food recognition using Google's Vision AI. Perfect balance of quality and cost.")
                        
                        Text("• **OpenAI (ChatGPT API)**: Most accurate AI analysis using GPT-4 Vision. Requires API key (~$0.01 per image). Excellent at image analysis and natural language queries.")
                        
                        Text("• **OpenFoodFacts**: Free, open database with extensive barcode coverage and text search for packaged foods. Default for text and barcode searches.")
                        
                        Text("• **USDA FoodData Central**: Free, official nutrition database. Superior nutrition data for non-packaged foods like fruits, vegetables, and meat.")
                        
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Section(header: Text("Search Type Recommendations")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Group {
                            Text("**Text/Voice Search:**")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text("USDA FoodData Central → OpenFoodFacts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("**Barcode Scanning:**")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text("OpenFoodFacts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("**AI Image Analysis:**")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text("Google (Gemini API) → OpenAI (ChatGPT API) → Anthropic (Claude API)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                } // End if foodSearchEnabled
                
                Section(header: Text("Medical Disclaimer")) {
                    Text("AI nutritional estimates are approximations only. Always consult with your healthcare provider for medical decisions. Verify nutritional information whenever possible. Use at your own risk.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Food Search Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    // Restore original values (discard changes)
                    claudeKey = ConfigurableAIService.shared.getAPIKey(for: .claude) ?? ""
                    claudeQuery = ConfigurableAIService.shared.getQuery(for: .claude) ?? ""
                    openAIKey = ConfigurableAIService.shared.getAPIKey(for: .openAI) ?? ""
                    openAIQuery = ConfigurableAIService.shared.getQuery(for: .openAI) ?? ""
                    googleGeminiKey = ConfigurableAIService.shared.getAPIKey(for: .googleGemini) ?? ""
                    googleGeminiQuery = ConfigurableAIService.shared.getQuery(for: .googleGemini) ?? ""
                    foodSearchEnabled = UserDefaults.standard.foodSearchEnabled  // Restore original feature flag state
                    advancedDosingRecommendationsEnabled = UserDefaults.standard.advancedDosingRecommendationsEnabled  // Restore original advanced dosing flag state
                    
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.secondary),
                trailing: Button("Save") {
                    saveSettings()
                }
                .font(.headline)
                .foregroundColor(.accentColor)
            )
        }
        .alert("API Key Required", isPresented: $showingAPIKeyAlert) {
            Button("OK") { }
        } message: {
            Text("This AI provider requires an API key. Please enter your API key in the settings below.")
        }
    }
    
    @ViewBuilder
    private var analysisModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode picker
            Picker("Analysis Mode", selection: Binding(
                get: { aiService.analysisMode },
                set: { newMode in aiService.setAnalysisMode(newMode) }
            )) {
                ForEach(ConfigurableAIService.AnalysisMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            currentModeDetails
            modelInformation
        }
    }
    
    @ViewBuilder
    private var currentModeDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: aiService.analysisMode.iconName)
                    .foregroundColor(aiService.analysisMode.iconColor)
                Text("Current Mode: \(aiService.analysisMode.displayName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Text(aiService.analysisMode.detailedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(aiService.analysisMode.backgroundColor)
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var modelInformation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Models Used:")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                modelRow(provider: "Google Gemini:", model: ConfigurableAIService.optimalModel(for: .googleGemini, mode: aiService.analysisMode))
                modelRow(provider: "OpenAI:", model: ConfigurableAIService.optimalModel(for: .openAI, mode: aiService.analysisMode))
                modelRow(provider: "Claude:", model: ConfigurableAIService.optimalModel(for: .claude, mode: aiService.analysisMode))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
    
    @ViewBuilder
    private func modelRow(provider: String, model: String) -> some View {
        HStack {
            Text(provider)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(model)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
    
    private func saveSettings() {
        // Save all current settings to UserDefaults
        // Feature flag settings
        UserDefaults.standard.foodSearchEnabled = foodSearchEnabled
        UserDefaults.standard.advancedDosingRecommendationsEnabled = advancedDosingRecommendationsEnabled
        UserDefaults.standard.useGPT5ForOpenAI = useGPT5ForOpenAI
        
        // API key and query settings
        aiService.setAPIKey(claudeKey, for: .claude)
        aiService.setAPIKey(openAIKey, for: .openAI)
        aiService.setAPIKey(googleGeminiKey, for: .googleGemini)
        aiService.setQuery(claudeQuery, for: .claude)
        aiService.setQuery(openAIQuery, for: .openAI)
        aiService.setQuery(googleGeminiQuery, for: .googleGemini)
        
        // Search type provider settings are automatically saved via the Binding
        // No additional action needed as they update UserDefaults directly
        
        
        // Dismiss the settings view
        presentationMode.wrappedValue.dismiss()
    }
    
    private func getBindingForSearchType(_ searchType: SearchType) -> Binding<SearchProvider> {
        switch searchType {
        case .textSearch:
            return Binding(
                get: { aiService.textSearchProvider },
                set: { newValue in
                    aiService.textSearchProvider = newValue
                    UserDefaults.standard.textSearchProvider = newValue.rawValue
                }
            )
        case .barcodeSearch:
            return Binding(
                get: { aiService.barcodeSearchProvider },
                set: { newValue in
                    aiService.barcodeSearchProvider = newValue
                    UserDefaults.standard.barcodeSearchProvider = newValue.rawValue
                }
            )
        case .aiImageSearch:
            return Binding(
                get: { aiService.aiImageSearchProvider },
                set: { newValue in
                    aiService.aiImageSearchProvider = newValue
                    UserDefaults.standard.aiImageProvider = newValue.rawValue
                }
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AISettingsView()
    }
}
#endif
