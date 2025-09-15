//
//  UserDefaults+Loop.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit


extension UserDefaults {
    private enum Key: String {
        case legacyPumpManagerState = "com.loopkit.Loop.PumpManagerState"
        case legacyCGMManagerState = "com.loopkit.Loop.CGMManagerState"
        case legacyServicesState = "com.loopkit.Loop.ServicesState"
        case loopNotRunningNotifications = "com.loopkit.Loop.loopNotRunningNotifications"
        case inFlightAutomaticDose = "com.loopkit.Loop.inFlightAutomaticDose"
        case favoriteFoods = "com.loopkit.Loop.favoriteFoods"
        case aiProvider = "com.loopkit.Loop.aiProvider"
        case claudeAPIKey = "com.loopkit.Loop.claudeAPIKey"
        case claudeQuery = "com.loopkit.Loop.claudeQuery"
        case openAIAPIKey = "com.loopkit.Loop.openAIAPIKey"
        case openAIQuery = "com.loopkit.Loop.openAIQuery"
        case googleGeminiAPIKey = "com.loopkit.Loop.googleGeminiAPIKey"
        case googleGeminiQuery = "com.loopkit.Loop.googleGeminiQuery"
        case usdaAPIKey = "com.loopkit.Loop.usdaAPIKey"
        case customAIBaseURL = "com.loopkit.Loop.customAIBaseURL"
        case customAIAPIKey = "com.loopkit.Loop.customAIAPIKey"
        case customAIModel = "com.loopkit.Loop.customAIModel"
        case customAIAPIVersion = "com.loopkit.Loop.customAIAPIVersion"
        case customAIOrganization = "com.loopkit.Loop.customAIOrganization"
        case customAIEndpointPath = "com.loopkit.Loop.customAIEndpointPath"
        case textSearchProvider = "com.loopkit.Loop.textSearchProvider"
        case barcodeSearchProvider = "com.loopkit.Loop.barcodeSearchProvider"
        case aiImageProvider = "com.loopkit.Loop.aiImageProvider"
        case analysisMode = "com.loopkit.Loop.analysisMode"
        case foodSearchEnabled = "com.loopkit.Loop.foodSearchEnabled"
        case advancedDosingRecommendationsEnabled = "com.loopkit.Loop.advancedDosingRecommendationsEnabled"
        case useGPT5ForOpenAI = "com.loopkit.Loop.useGPT5ForOpenAI"
        case favoriteFoodImageIDs = "com.loopkit.Loop.favoriteFoodImageIDs"
    }

    var legacyPumpManagerRawValue: PumpManager.RawValue? {
        get {
            return dictionary(forKey: Key.legacyPumpManagerState.rawValue)
        }
    }
    func clearLegacyPumpManagerRawValue() {
        set(nil, forKey: Key.legacyPumpManagerState.rawValue)
    }


    var legacyCGMManagerRawValue: CGMManager.RawValue? {
        get {
            return dictionary(forKey: Key.legacyCGMManagerState.rawValue)
        }
    }

    func clearLegacyCGMManagerRawValue() {
        set(nil, forKey: Key.legacyCGMManagerState.rawValue)
    }

    var legacyServicesState: [Service.RawStateValue] {
        get {
            return array(forKey: Key.legacyServicesState.rawValue) as? [[String: Any]] ?? []
        }
    }

    func clearLegacyServicesState() {
        set(nil, forKey: Key.legacyServicesState.rawValue)
    }

    var inFlightAutomaticDose: AutomaticDoseRecommendation? {
        get {
            let decoder = JSONDecoder()
            guard let data = object(forKey: Key.inFlightAutomaticDose.rawValue) as? Data else {
                return nil
            }
            return try? decoder.decode(AutomaticDoseRecommendation.self, from: data)
        }
        set {
            do {
                if let newValue = newValue {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(newValue)
                    set(data, forKey: Key.inFlightAutomaticDose.rawValue)
                } else {
                    set(nil, forKey: Key.inFlightAutomaticDose.rawValue)
                }
            } catch {
                assertionFailure("Unable to encode AutomaticDoseRecommendation")
            }
        }
    }

    var loopNotRunningNotifications: [StoredLoopNotRunningNotification] {
        get {
            let decoder = JSONDecoder()
            guard let data = object(forKey: Key.loopNotRunningNotifications.rawValue) as? Data else {
                return []
            }
            return (try? decoder.decode([StoredLoopNotRunningNotification].self, from: data)) ?? []
        }
        set {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(newValue)
                set(data, forKey: Key.loopNotRunningNotifications.rawValue)
            } catch {
                assertionFailure("Unable to encode Loop not running notification")
            }
        }
    }
    
    var favoriteFoods: [StoredFavoriteFood] {
        get {
            let decoder = JSONDecoder()
            guard let data = object(forKey: Key.favoriteFoods.rawValue) as? Data else {
                return []
            }
            return (try? decoder.decode([StoredFavoriteFood].self, from: data)) ?? []
        }
        set {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(newValue)
                set(data, forKey: Key.favoriteFoods.rawValue)
            } catch {
                assertionFailure("Unable to encode stored favorite foods")
            }
        }
    }

    /// Persist favorite foods with explicit call and lightweight logging.
    /// Use this after user-initiated changes to avoid race conditions between multiple view models.
    func writeFavoriteFoods(_ newValue: [StoredFavoriteFood]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(newValue)
            set(data, forKey: Key.favoriteFoods.rawValue)
            #if DEBUG
            print("💾 Saved favorite foods count: \(newValue.count)")
            #endif
        } catch {
            assertionFailure("Unable to encode stored favorite foods (explicit write)")
        }
    }
    
    var aiProvider: String {
        get {
            return string(forKey: Key.aiProvider.rawValue) ?? "Basic Analysis (Free)"
        }
        set {
            set(newValue, forKey: Key.aiProvider.rawValue)
        }
    }
    
    var claudeAPIKey: String {
        get {
            return string(forKey: Key.claudeAPIKey.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: Key.claudeAPIKey.rawValue)
        }
    }
    
    var claudeQuery: String {
        get {
            return string(forKey: Key.claudeQuery.rawValue) ?? """
You are a nutrition expert analyzing this food image for diabetes management. Describe EXACTLY what you see in vivid detail.

EXAMPLE of the detailed description I expect:
"I can see a white ceramic dinner plate, approximately 10 inches in diameter, containing three distinct food items. The main protein appears to be a grilled chicken breast, about 5 inches long and 1 inch thick, with visible grill marks in a crosshatch pattern indicating high-heat cooking..."

RESPOND ONLY IN JSON FORMAT with these exact fields:
{
  "food_items": [
    {
      "name": "specific food name with exact preparation detail I can see",
      "portion_estimate": "exact portion with visual references",
      "preparation_method": "specific cooking details I observe",
      "visual_cues": "exact visual elements I'm analyzing",
      "carbohydrates": number_in_grams_for_this_exact_portion,
      "protein": number_in_grams_for_this_exact_portion,
      "fat": number_in_grams_for_this_exact_portion,
      "calories": number_in_kcal_for_this_exact_portion,
      "serving_multiplier": decimal_representing_how_many_standard_servings,
      "assessment_notes": "step-by-step explanation of how I calculated this portion"
    }
  ],
  "overall_description": "COMPREHENSIVE visual inventory of everything I can see",
  "total_carbohydrates": sum_of_all_carbs,
  "total_protein": sum_of_all_protein,
  "total_fat": sum_of_all_fat,
  "total_calories": sum_of_all_calories,
  "portion_assessment_method": "Step-by-step description of my measurement process",
  "confidence": decimal_between_0_and_1,
  "diabetes_considerations": "Based on what I can see: specific carb sources and timing considerations",
  "visual_assessment_details": "Detailed texture, color, cooking, and quality analysis"
}

MANDATORY REQUIREMENTS:
❌ NEVER say "mixed vegetables" - specify "steamed broccoli florets, diced carrots"
❌ NEVER say "chicken" - specify "grilled chicken breast with char marks"
❌ NEVER say "average portion" - specify "5 oz portion covering 1/4 of plate"
✅ ALWAYS describe exact colors, textures, sizes, shapes, cooking evidence
✅ ALWAYS compare portions to visible objects (fork, plate, hand if visible)
✅ ALWAYS calculate nutrition from YOUR visual portion assessment
"""
        }
        set {
            set(newValue, forKey: Key.claudeQuery.rawValue)
        }
    }
    
    var openAIAPIKey: String {
        get {
            return string(forKey: Key.openAIAPIKey.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: Key.openAIAPIKey.rawValue)
        }
    }
    
    var openAIQuery: String {
        get {
            // Check if using GPT-5 - use optimized prompt for better performance
            if UserDefaults.standard.useGPT5ForOpenAI {
                return string(forKey: Key.openAIQuery.rawValue) ?? """
Analyze this food image for diabetes management. Be specific and accurate.

JSON format required:
{
  "food_items": [{
    "name": "specific food name with preparation details",
    "portion_estimate": "portion size with visual reference", 
    "carbohydrates": grams_number,
    "protein": grams_number,
    "fat": grams_number,
    "calories": kcal_number,
    "serving_multiplier": decimal_servings
  }],
  "overall_description": "detailed visual description",
  "total_carbohydrates": sum_carbs,
  "total_protein": sum_protein, 
  "total_fat": sum_fat,
  "total_calories": sum_calories,
  "confidence": decimal_0_to_1,
  "diabetes_considerations": "carb sources and timing advice"
}

Requirements: Use exact visual details, compare to visible objects, calculate from visual assessment.
"""
            } else {
                // Full detailed prompt for GPT-4 models
                return string(forKey: Key.openAIQuery.rawValue) ?? """
You are a nutrition expert analyzing this food image for diabetes management. Describe EXACTLY what you see in vivid detail.

EXAMPLE of the detailed description I expect:
"I can see a white ceramic dinner plate, approximately 10 inches in diameter, containing three distinct food items. The main protein appears to be a grilled chicken breast, about 5 inches long and 1 inch thick, with visible grill marks in a crosshatch pattern indicating high-heat cooking..."

RESPOND ONLY IN JSON FORMAT with these exact fields:
{
  "food_items": [
    {
      "name": "specific food name with exact preparation detail I can see",
      "portion_estimate": "exact portion with visual references",
      "preparation_method": "specific cooking details I observe",
      "visual_cues": "exact visual elements I'm analyzing",
      "carbohydrates": number_in_grams_for_this_exact_portion,
      "protein": number_in_grams_for_this_exact_portion,
      "fat": number_in_grams_for_this_exact_portion,
      "calories": number_in_kcal_for_this_exact_portion,
      "serving_multiplier": decimal_representing_how_many_standard_servings,
      "assessment_notes": "step-by-step explanation of how I calculated this portion"
    }
  ],
  "overall_description": "COMPREHENSIVE visual inventory of everything I can see",
  "total_carbohydrates": sum_of_all_carbs,
  "total_protein": sum_of_all_protein,
  "total_fat": sum_of_all_fat,
  "total_calories": sum_of_all_calories,
  "portion_assessment_method": "Step-by-step description of my measurement process",
  "confidence": decimal_between_0_and_1,
  "diabetes_considerations": "Based on what I can see: specific carb sources and timing considerations",
  "visual_assessment_details": "Detailed texture, color, cooking, and quality analysis"
}

MANDATORY REQUIREMENTS:
❌ NEVER say "mixed vegetables" - specify "steamed broccoli florets, diced carrots"
❌ NEVER say "chicken" - specify "grilled chicken breast with char marks"
❌ NEVER say "average portion" - specify "5 oz portion covering 1/4 of plate"
✅ ALWAYS describe exact colors, textures, sizes, shapes, cooking evidence
✅ ALWAYS compare portions to visible objects (fork, plate, hand if visible)
✅ ALWAYS calculate nutrition from YOUR visual portion assessment
"""
            }
        }
        set {
            set(newValue, forKey: Key.openAIQuery.rawValue)
        }
    }
    
    
    var googleGeminiAPIKey: String {
        get {
            return string(forKey: Key.googleGeminiAPIKey.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: Key.googleGeminiAPIKey.rawValue)
        }
    }

    // Optional: API key for USDA FoodData Central (improves reliability vs DEMO_KEY)
    var usdaAPIKey: String {
        get { string(forKey: Key.usdaAPIKey.rawValue) ?? "" }
        set { set(newValue, forKey: Key.usdaAPIKey.rawValue) }
    }

    // Bring Your Own (OpenAI-compatible) provider configuration
    var customAIBaseURL: String {
        get { string(forKey: Key.customAIBaseURL.rawValue) ?? "" }
        set { set(newValue, forKey: Key.customAIBaseURL.rawValue) }
    }
    var customAIAPIKey: String {
        get { string(forKey: Key.customAIAPIKey.rawValue) ?? "" }
        set { set(newValue, forKey: Key.customAIAPIKey.rawValue) }
    }
    var customAIModel: String {
        get { string(forKey: Key.customAIModel.rawValue) ?? "" }
        set { set(newValue, forKey: Key.customAIModel.rawValue) }
    }
    var customAIAPIVersion: String {
        get { string(forKey: Key.customAIAPIVersion.rawValue) ?? "" }
        set { set(newValue, forKey: Key.customAIAPIVersion.rawValue) }
    }
    var customAIOrganization: String {
        get { string(forKey: Key.customAIOrganization.rawValue) ?? "" }
        set { set(newValue, forKey: Key.customAIOrganization.rawValue) }
    }
    // Optional custom endpoint path for non-Azure OpenAI-compatible providers
    // Example: "/v1/chat/completions" (default) or "/openai/v1/chat/completions"
    var customAIEndpointPath: String {
        get { string(forKey: Key.customAIEndpointPath.rawValue) ?? "" }
        set { set(newValue, forKey: Key.customAIEndpointPath.rawValue) }
    }
    
    var googleGeminiQuery: String {
        get {
            return string(forKey: Key.googleGeminiQuery.rawValue) ?? """
You are a nutrition expert analyzing this food image for diabetes management. Describe EXACTLY what you see in vivid detail.

EXAMPLE of the detailed description I expect:
"I can see a white ceramic dinner plate, approximately 10 inches in diameter, containing three distinct food items. The main protein appears to be a grilled chicken breast, about 5 inches long and 1 inch thick, with visible grill marks in a crosshatch pattern indicating high-heat cooking..."

RESPOND ONLY IN JSON FORMAT with these exact fields:
{
  "food_items": [
    {
      "name": "specific food name with exact preparation detail I can see",
      "portion_estimate": "exact portion with visual references",
      "preparation_method": "specific cooking details I observe",
      "visual_cues": "exact visual elements I'm analyzing",
      "carbohydrates": number_in_grams_for_this_exact_portion,
      "protein": number_in_grams_for_this_exact_portion,
      "fat": number_in_grams_for_this_exact_portion,
      "calories": number_in_kcal_for_this_exact_portion,
      "serving_multiplier": decimal_representing_how_many_standard_servings,
      "assessment_notes": "step-by-step explanation of how I calculated this portion"
    }
  ],
  "overall_description": "COMPREHENSIVE visual inventory of everything I can see",
  "total_carbohydrates": sum_of_all_carbs,
  "total_protein": sum_of_all_protein,
  "total_fat": sum_of_all_fat,
  "total_calories": sum_of_all_calories,
  "portion_assessment_method": "Step-by-step description of my measurement process",
  "confidence": decimal_between_0_and_1,
  "diabetes_considerations": "Based on what I can see: specific carb sources and timing considerations",
  "visual_assessment_details": "Detailed texture, color, cooking, and quality analysis"
}

MANDATORY REQUIREMENTS:
❌ NEVER say "mixed vegetables" - specify "steamed broccoli florets, diced carrots"
❌ NEVER say "chicken" - specify "grilled chicken breast with char marks"
❌ NEVER say "average portion" - specify "5 oz portion covering 1/4 of plate"
✅ ALWAYS describe exact colors, textures, sizes, shapes, cooking evidence
✅ ALWAYS compare portions to visible objects (fork, plate, hand if visible)
✅ ALWAYS calculate nutrition from YOUR visual portion assessment
"""
        }
        set {
            set(newValue, forKey: Key.googleGeminiQuery.rawValue)
        }
    }
    
    var textSearchProvider: String {
        get {
            // Default to USDA for first-time users
            return string(forKey: Key.textSearchProvider.rawValue) ?? "USDA FoodData Central"
        }
        set {
            set(newValue, forKey: Key.textSearchProvider.rawValue)
        }
    }
    
    var barcodeSearchProvider: String {
        get {
            return string(forKey: Key.barcodeSearchProvider.rawValue) ?? "OpenFoodFacts (Default)"
        }
        set {
            set(newValue, forKey: Key.barcodeSearchProvider.rawValue)
        }
    }
    
    var aiImageProvider: String {
        get {
            // Default to OpenAI for first-time users
            return string(forKey: Key.aiImageProvider.rawValue) ?? "OpenAI (ChatGPT API)"
        }
        set {
            set(newValue, forKey: Key.aiImageProvider.rawValue)
        }
    }
    
    var analysisMode: String {
        get {
            return string(forKey: Key.analysisMode.rawValue) ?? "standard"
        }
        set {
            set(newValue, forKey: Key.analysisMode.rawValue)
        }
    }
    
    var foodSearchEnabled: Bool {
        get {
            return bool(forKey: Key.foodSearchEnabled.rawValue)
        }
        set {
            set(newValue, forKey: Key.foodSearchEnabled.rawValue)
        }
    }

    // Alias for rebranding: FoodFinder -> maps to Food Search flag
    var foodFinderEnabled: Bool {
        get { foodSearchEnabled }
        set { foodSearchEnabled = newValue }
    }
    
    var advancedDosingRecommendationsEnabled: Bool {
        get {
            return bool(forKey: Key.advancedDosingRecommendationsEnabled.rawValue)
        }
        set {
            set(newValue, forKey: Key.advancedDosingRecommendationsEnabled.rawValue)
        }
    }
    
    var useGPT5ForOpenAI: Bool {
        get {
            return bool(forKey: Key.useGPT5ForOpenAI.rawValue)
        }
        set {
            set(newValue, forKey: Key.useGPT5ForOpenAI.rawValue)
        }
    }

    // Mapping of FavoriteFood.id -> image identifier (filename in image store)
    var favoriteFoodImageIDs: [String: String] {
        get {
            return dictionary(forKey: Key.favoriteFoodImageIDs.rawValue) as? [String: String] ?? [:]
        }
        set {
            set(newValue, forKey: Key.favoriteFoodImageIDs.rawValue)
        }
    }
}
