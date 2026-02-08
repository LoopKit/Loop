//
//  FoodFinder_FeatureFlags.swift
//  Loop
//
//  FoodFinder — AI-powered food/barcode scanning for carb entry.
//  This is the single feature-toggle and configuration file.
//  All FoodFinder enable/disable logic lives here.
//

import Foundation
import LoopKit

// MARK: - Feature Toggle

/// Central on/off switch for the entire FoodFinder feature.
/// Loop host files check `FoodFinder_FeatureFlags.isEnabled` to gate UI insertion.
enum FoodFinder_FeatureFlags {
    /// Master toggle — persisted in UserDefaults.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.foodSearchEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.foodSearchEnabled) }
    }
}

// MARK: - UserDefaults Keys

/// All FoodFinder-specific UserDefaults keys live here, not in Loop's UserDefaults+Loop.swift.
/// This keeps the host codebase clean and makes the feature self-contained.
extension FoodFinder_FeatureFlags {
    enum Keys {
        // Feature toggle
        static let foodSearchEnabled                = "com.loopkit.Loop.foodSearchEnabled"

        // Favorite food thumbnails
        static let favoriteFoodImageIDs             = "com.loopkit.Loop.favoriteFoodImageIDs"

        // AI Provider selection
        static let aiProvider                       = "com.loopkit.Loop.aiProvider"
        static let analysisMode                     = "com.loopkit.Loop.analysisMode"
        static let useGPT5ForOpenAI                 = "com.loopkit.Loop.useGPT5ForOpenAI"

        // Claude
        static let claudeAPIKey                     = "com.loopkit.Loop.claudeAPIKey"
        static let claudeQuery                      = "com.loopkit.Loop.claudeQuery"

        // OpenAI
        static let openAIAPIKey                     = "com.loopkit.Loop.openAIAPIKey"
        static let openAIQuery                      = "com.loopkit.Loop.openAIQuery"

        // Google Gemini
        static let googleGeminiAPIKey               = "com.loopkit.Loop.googleGeminiAPIKey"
        static let googleGeminiQuery                = "com.loopkit.Loop.googleGeminiQuery"

        // USDA
        static let usdaAPIKey                       = "com.loopkit.Loop.usdaAPIKey"

        // Custom / Bring-Your-Own AI provider
        static let customAIBaseURL                  = "com.loopkit.Loop.customAIBaseURL"
        static let customAIAPIKey                   = "com.loopkit.Loop.customAIAPIKey"
        static let customAIModel                    = "com.loopkit.Loop.customAIModel"
        static let customAIAPIVersion               = "com.loopkit.Loop.customAIAPIVersion"
        static let customAIOrganization             = "com.loopkit.Loop.customAIOrganization"
        static let customAIEndpointPath             = "com.loopkit.Loop.customAIEndpointPath"

        // Search provider routing
        static let textSearchProvider               = "com.loopkit.Loop.textSearchProvider"
        static let barcodeSearchProvider            = "com.loopkit.Loop.barcodeSearchProvider"
        static let aiImageProvider                  = "com.loopkit.Loop.aiImageProvider"

        // Advanced dosing (FoodFinder-related)
        static let advancedDosingRecommendationsEnabled = "com.loopkit.Loop.advancedDosingRecommendationsEnabled"
    }
}

// MARK: - Convenience Accessors

/// UserDefaults convenience properties for FoodFinder settings.
/// Other FoodFinder files access these instead of raw key strings.
extension UserDefaults {

    // MARK: Feature Toggle

    var foodFinderEnabled: Bool {
        get { bool(forKey: FoodFinder_FeatureFlags.Keys.foodSearchEnabled) }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.foodSearchEnabled) }
    }

    // MARK: Favorite Food Thumbnails

    var favoriteFoodImageIDs: [String: String] {
        get { dictionary(forKey: FoodFinder_FeatureFlags.Keys.favoriteFoodImageIDs) as? [String: String] ?? [:] }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.favoriteFoodImageIDs) }
    }

    /// Persist favorite foods with explicit call and lightweight logging.
    func foodFinder_writeFavoriteFoods(_ newValue: [StoredFavoriteFood]) {
        do {
            let data = try JSONEncoder().encode(newValue)
            set(data, forKey: "com.loopkit.Loop.favoriteFoods")
            #if DEBUG
            print("FoodFinder: Saved favorite foods count: \(newValue.count)")
            #endif
        } catch {
            assertionFailure("FoodFinder: Unable to encode stored favorite foods")
        }
    }

    // MARK: AI Provider

    var foodFinder_aiProvider: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.aiProvider) ?? "Basic Analysis (Free)" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.aiProvider) }
    }

    var foodFinder_analysisMode: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.analysisMode) ?? "standard" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.analysisMode) }
    }

    var foodFinder_useGPT5ForOpenAI: Bool {
        get { bool(forKey: FoodFinder_FeatureFlags.Keys.useGPT5ForOpenAI) }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.useGPT5ForOpenAI) }
    }

    // MARK: Claude

    var foodFinder_claudeAPIKey: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.claudeAPIKey) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.claudeAPIKey) }
    }

    var foodFinder_claudeQuery: String {
        get {
            return string(forKey: FoodFinder_FeatureFlags.Keys.claudeQuery) ?? """
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
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.claudeQuery) }
    }

    // MARK: OpenAI

    var foodFinder_openAIAPIKey: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.openAIAPIKey) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.openAIAPIKey) }
    }

    var foodFinder_openAIQuery: String {
        get {
            if UserDefaults.standard.foodFinder_useGPT5ForOpenAI {
                return string(forKey: FoodFinder_FeatureFlags.Keys.openAIQuery) ?? """
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
                return string(forKey: FoodFinder_FeatureFlags.Keys.openAIQuery) ?? """
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
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.openAIQuery) }
    }

    // MARK: Google Gemini

    var foodFinder_googleGeminiAPIKey: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.googleGeminiAPIKey) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.googleGeminiAPIKey) }
    }

    var foodFinder_googleGeminiQuery: String {
        get {
            return string(forKey: FoodFinder_FeatureFlags.Keys.googleGeminiQuery) ?? """
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
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.googleGeminiQuery) }
    }

    // MARK: USDA

    var foodFinder_usdaAPIKey: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.usdaAPIKey) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.usdaAPIKey) }
    }

    // MARK: Custom / Bring-Your-Own AI Provider

    var foodFinder_customAIBaseURL: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIBaseURL) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIBaseURL) }
    }

    var foodFinder_customAIAPIKey: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIAPIKey) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIAPIKey) }
    }

    var foodFinder_customAIModel: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIModel) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIModel) }
    }

    var foodFinder_customAIAPIVersion: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIAPIVersion) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIAPIVersion) }
    }

    var foodFinder_customAIOrganization: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIOrganization) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIOrganization) }
    }

    var foodFinder_customAIEndpointPath: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.customAIEndpointPath) ?? "" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.customAIEndpointPath) }
    }

    // MARK: Search Provider Routing

    var foodFinder_textSearchProvider: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.textSearchProvider) ?? "USDA FoodData Central" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.textSearchProvider) }
    }

    var foodFinder_barcodeSearchProvider: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.barcodeSearchProvider) ?? "OpenFoodFacts (Default)" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.barcodeSearchProvider) }
    }

    var foodFinder_aiImageProvider: String {
        get { string(forKey: FoodFinder_FeatureFlags.Keys.aiImageProvider) ?? "OpenAI (ChatGPT API)" }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.aiImageProvider) }
    }

    // MARK: Advanced

    var foodFinder_advancedDosingRecommendationsEnabled: Bool {
        get { bool(forKey: FoodFinder_FeatureFlags.Keys.advancedDosingRecommendationsEnabled) }
        set { set(newValue, forKey: FoodFinder_FeatureFlags.Keys.advancedDosingRecommendationsEnabled) }
    }
}
