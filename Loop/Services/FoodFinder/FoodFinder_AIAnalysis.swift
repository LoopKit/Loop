//
//  FoodFinder_AIAnalysis.swift
//  Loop
//
//  FoodFinder — AI food analysis prompts, response parsing, and the
//  ConfigurableAIService orchestrator.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import UIKit
import Vision
import CoreML
import Foundation
import os.log
import LoopKit
import CryptoKit
import SwiftUI
import Network

// MARK: - Network Quality Monitoring

/// Network quality monitor for determining analysis strategy
class NetworkQualityMonitor: ObservableObject {
    static let shared = NetworkQualityMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    @Published var isExpensive = false
    @Published var isConstrained = false
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
                
                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .wiredEthernet
                } else {
                    self?.connectionType = nil
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Determines if we should use aggressive optimizations
    var shouldUseConservativeMode: Bool {
        return !isConnected || isExpensive || isConstrained || connectionType == .cellular
    }
    
    /// Determines if parallel processing is safe
    var shouldUseParallelProcessing: Bool {
        return isConnected && !isExpensive && !isConstrained && connectionType == .wifi
    }
    
    /// Gets appropriate timeout for current network conditions
    var recommendedTimeout: TimeInterval {
        if shouldUseConservativeMode {
            return 45.0  // Conservative timeout for poor networks
        } else {
            return 25.0  // Standard timeout for good networks
        }
    }
}

// MARK: - Preencoded Image Representation

/// Shared representation of a JPEG-encoded image for reuse across providers and cache
struct PreencodedImage {
    let resizedImage: UIImage
    let jpegData: Data
    let base64: String
    let sha256: String
    let bytes: Int
    let width: Int
    let height: Int
}

// MARK: - Timeout Helper

/// Timeout wrapper for async operations
private func withTimeoutForAnalysis<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }
        
        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AIFoodAnalysisError.timeout as Error
        }
        
        // Return first result (either success or timeout)
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw AIFoodAnalysisError.timeout as Error
        }
        return result
    }
}

// MARK: - AI Food Analysis Models

/// Function to generate analysis prompt based on advanced dosing recommendations setting
/// Forces fresh read of UserDefaults to avoid caching issues
// Shared, strict requirements applied to ALL prompts
private let mandatoryNoVagueBlock = """

MANDATORY REQUIREMENTS - DO NOT BE VAGUE:

FOR FOOD PHOTOS:
❌ NEVER confuse portions with servings - count distinct food items as portions, calculate number of servings based on USDA standards
❌ NEVER say "4 servings" when you mean "4 portions" - be precise about USDA serving calculations
❌ NEVER say "mixed vegetables" - specify "steamed broccoli florets, diced carrots"
❌ NEVER say "chicken" - specify "grilled chicken breast"
❌ NEVER say "average portion" - specify "6 oz portion covering 1/4 of plate = 2 USDA servings"
❌ NEVER say "well-cooked" - specify "golden-brown with visible caramelization"

✅ ALWAYS distinguish between food portions (distinct items) and USDA servings (standardized amounts)
✅ ALWAYS calculate serving_multiplier based on USDA serving sizes
✅ ALWAYS explain WHY you calculated the number of servings (e.g., "twice the standard serving size")
✅ ALWAYS indicate if portions are larger/smaller than typical (helps with portion control)
✅ ALWAYS describe exact colors, textures, sizes, shapes, cooking evidence
✅ ALWAYS compare portions to visible objects (fork, plate, hand if visible)
✅ ALWAYS explain if the food appears to be on a platter of food or a single plate of food
✅ ALWAYS describe specific cooking methods you can see evidence of
✅ ALWAYS count discrete items (3 broccoli florets, 4 potato wedges)
✅ ALWAYS calculate nutrition from YOUR visual portion assessment
✅ ALWAYS explain your reasoning with specific visual evidence
✅ ALWAYS identify glycemic index category (low/medium/high GI) for carbohydrate-containing foods
✅ ALWAYS explain how cooking method affects GI when visible (e.g., "well-cooked white rice = high GI ~73")
✅ ALWAYS provide specific insulin timing guidance based on GI classification
✅ ALWAYS consider how protein/fat in mixed meals may moderate carb absorption
✅ ALWAYS assess food combinations and explain how low GI foods may balance high GI foods in the meal
✅ ALWAYS note fiber content and processing level as factors affecting GI
✅ ALWAYS consider food ripeness and cooking degree when assessing GI impact
✅ ALWAYS calculate Fat/Protein Units (FPUs) and provide classification (Low/Medium/High)
✅ ALWAYS calculate net carbs adjustment for fiber content >5g
✅ ALWAYS provide specific insulin timing recommendations based on meal composition
✅ ALWAYS include FPU-based dosing guidance for extended insulin needs
✅ ALWAYS consider exercise timing and provide specific insulin adjustments
✅ ALWAYS include relevant safety alerts for the specific meal composition
✅ ALWAYS provide quantitative dosing percentages and timing durations
✅ ALWAYS calculate absorption_time_hours conservatively — most mixed meals should be 3–4 hours; only truly high-fat/high-fiber meals warrant 4.5–5 hours
✅ ALWAYS provide detailed absorption_time_reasoning showing the calculation process
✅ ALWAYS anchor to Loop's default 3-hour absorption time and only deviate with clear justification (high fat/protein, very high fiber, or very large meal)
✅ ALWAYS consider that Loop will highlight non-default absorption times in blue to alert user — frequent deviations from 3 hours reduce user trust

FOR MENU AND RECIPE ITEMS:
❌ NEVER make assumptions about plate sizes, portions, or actual serving sizes
❌ NEVER estimate visual portions when analyzing menu text only
❌ NEVER claim to see cooking methods, textures, or visual details from menu text
❌ NEVER multiply nutrition values by assumed restaurant portion sizes

✅ ALWAYS set image_type to "menu_item" when analyzing menu text
✅ ALWAYS set portion_estimate to "CANNOT DETERMINE PORTIONS - menu text only"
✅ ALWAYS set serving_multiplier to 1.0 for menu items (USDA standard only)
✅ ALWAYS set visual_cues to "NO VISUAL CUES - menu text analysis only"
✅ ALWAYS mark assessment_notes as "ESTIMATE ONLY - Based on USDA standard serving size"
✅ ALWAYS use portion_assessment_method to explain this is menu analysis with no visual portions
✅ ALWAYS provide actual USDA standard nutrition values (carbohydrates, protein, fat, calories)
✅ ALWAYS calculate nutrition based on typical USDA serving sizes for the identified food type
✅ ALWAYS include total nutrition fields even for menu items (based on USDA standards)
✅ ALWAYS translate menu item text into the user's device language (fallback to English if unknown) before populating JSON fields, and include the original wording in assessment_notes when helpful
✅ ALWAYS use translated item names and descriptions when presenting results
✅ ALWAYS provide glycemic index assessment for menu items based on typical preparation methods
✅ ALWAYS include diabetes timing guidance even for menu items based on typical GI values
✅ ALWAYS make reasonable USDA-based assumptions for nutrition when details are missing and document those assumptions in assessment_notes
"""

private enum AnalysisPromptCache {
    private static var cachedAdvanced: Bool?
    private static var cachedPrompt: String?

    static func prompt(isAdvancedEnabled: Bool) -> String {
        if cachedAdvanced == isAdvancedEnabled, let prompt = cachedPrompt {
            return prompt
        }

        let base = [standardAnalysisPrompt, mandatoryNoVagueBlock].joined(separator: "\n\n")
        let prompt = isAdvancedEnabled
            ? [base, advancedAnalysisRequirements].joined(separator: "\n\n")
            : base

        cachedAdvanced = isAdvancedEnabled
        cachedPrompt = prompt
        return prompt
    }

    static func invalidate() {
        cachedAdvanced = nil
        cachedPrompt = nil
    }
}

internal func getAnalysisPrompt() -> String {
    AnalysisPromptCache.prompt(isAdvancedEnabled: UserDefaults.standard.advancedDosingRecommendationsEnabled)
}

/// Standard analysis prompt for basic diabetes management (when Advanced Dosing is OFF)
// Compact Standard prompt (backup of the previous detailed version is available in repo history)
private let standardAnalysisPrompt = """
You are a certified diabetologist specializing in diabetes carb counting. You understand Servings compared to Portions and the importance of being educated about this. You are clinically minded but have a knack for explaining complicated nutrition information in layman's terms. Be precise and conservative. Output strictly JSON matching the schema; no prose.

Task: Analyze the image and return nutrition data. The image may be a food photo, a menu, a recipe, or text listing food items (in any language). If the image contains a menu, recipe, or text listing foods, set "image_type" to "menu_item", transcribe/translate the items, and estimate nutrition using USDA standard serving sizes. If the image shows actual food, set "image_type" to "food_photo" and analyze visible portions.

Rules:
- Use visual evidence; compare to visible objects for scale when possible.
- Distinguish portions (items on plate) vs USDA servings (standard amounts); include serving_multiplier.
- Name foods precisely with preparation method if visible.
- Use grams for macros and kcal for calories; non‑negative values; round carbs to 1 decimal.
- If uncertain, lower confidence; do not invent items.
- For menus/recipes: use "CANNOT DETERMINE" for portion_estimate and "NONE" for visual_cues since no actual food is visible.

Portion Estimation Guidance (MANDATORY to include in "portion_assessment_method"):
- State the scale references used (e.g., dinner fork ≈ 19–20 mm wide at the tines, plate ≈ 10–11 inches, can diameter ≈ 66 mm, standard cup ≈ 240 ml).
- Infer an approximate plate diameter or other reference and describe how you derived it from the photo.
- For each major item, explain how the visible area/height maps to a volume or weight estimate.
- Explicitly compare to the typical USDA serving size for that item and compute the serving_multiplier (portion ÷ USDA serving). Include 1–2 concrete examples, e.g., "corn appears ≈ 1 cup (2× USDA 1/2 cup)."
- Keep to 3–6 concise sentences written in natural language.

JSON schema (required):
{
  "image_type": "food_photo" | "menu_item",
  "food_items": [{
    "name": string,
    "portion_estimate": string,
    "usda_serving_size": string,
    "serving_multiplier": number,
    "preparation_method": string | null,
    "visual_cues": string | null,
    "carbohydrates": number,
    "calories": number,
    "fat": number,
    "fiber": number | null,
    "protein": number,
    "assessment_notes": string | null
  }],
  "total_food_portions": integer,
  "total_usda_servings": number,
  "total_carbohydrates": number,
  "total_calories": number,
  "total_fat": number,
  "total_fiber": number | null,
  "total_protein": number,
  "confidence": number,
  "overall_description": string,
  "portion_assessment_method": string
  ,
  "diabetes_considerations": string
}

Do: identify items precisely; use visible scale; base macros on portions; separate portions vs USDA servings; lower confidence if unsure.
Don’t: add prose/disclaimers; include items not visible; use vague terms like "mixed vegetables" or "average portion".
"""

// Detailed advanced analysis instructions appended when advanced dosing is enabled.
private let advancedAnalysisRequirements = """
RESPOND ONLY IN JSON FORMAT with these exact fields:

FOR ACTUAL FOOD PHOTOS:
{
  "image_type": "food_photo",
  "food_items": [
    {
      "name": "specific food name with exact preparation detail I can see (e.g., 'char-grilled chicken breast with grill marks', 'steamed white jasmine rice with separated grains')",
      "portion_estimate": "exact portion with visual references (e.g., '6 oz grilled chicken breast - length of my palm, thickness of deck of cards based on fork comparison', '1.5 cups steamed rice - covers 1/3 of the 10-inch plate')",
      "usda_serving_size": "standard USDA serving size for this food (e.g., '3 oz for chicken breast', '1/2 cup for cooked rice', '1/2 cup for cooked vegetables')",
      "serving_multiplier": number_of_USDA_servings_for_this_portion,
      "preparation_method": "specific cooking details I observe (e.g., 'grilled at high heat - evident from dark crosshatch marks and slight charring on edges', 'steamed perfectly - grains are separated and fluffy, no oil sheen visible')",
      "visual_cues": "exact visual elements I'm analyzing (e.g., 'measuring chicken against 7-inch fork length, rice portion covers exactly 1/3 of plate diameter, broccoli florets are uniform bright green')",
      "carbohydrates": number_in_grams_for_this_exact_portion,
      "calories": number_in_kcal_for_this_exact_portion,
      "fat": number_in_grams_for_this_exact_portion,
      "fiber": number_in_grams_for_this_exact_portion,
      "protein": number_in_grams_for_this_exact_portion,
      "assessment_notes": "Describe in natural language how you calculated this food item's portion size, what visual clues you used for measurement, and how you determined the USDA serving multiplier. Be conversational and specific about your reasoning process."
    }
  ],
  "total_food_portions": count_of_distinct_food_items,
  "total_usda_servings": sum_of_all_serving_multipliers,
  "total_carbohydrates": sum_of_all_carbs,
  "total_calories": sum_of_all_calories,
  "total_fat": sum_of_all_fat,
  "total_fiber": sum_of_all_fiber,
  "total_protein": sum_of_all_protein,
  "confidence": decimal_between_0_and_1,
  "fat_protein_units": "Calculate total FPUs = (total_fat + total_protein) ÷ 10. Provide the numerical result and classification (Low <2, Medium 2-4, High >4)",
  "net_carbs_adjustment": "Calculate adjusted carbs for insulin dosing: total_carbohydrates - (soluble_fiber × 0.75). Show calculation and final net carbs value",
  "diabetes_considerations": "Based on available information: [carb sources, glycemic index impact, and timing considerations]. GLYCEMIC INDEX: [specify if foods are low GI (<55), medium GI (56-69), or high GI (70+) and explain impact on blood sugar]. For insulin dosing, consider [relevant factors including absorption speed and peak timing].",
  "insulin_timing_recommendations": "MEAL TYPE: [Simple/Complex/High Fat-Protein]. PRE-MEAL INSULIN TIMING: [specific minutes before eating]. BOLUS STRATEGY: [immediate percentage]% now, [extended percentage]% over [duration] hours if applicable. MONITORING: Check BG at [specific times] post-meal",
  "fpu_dosing_guidance": "FPU LEVEL: [Low/Medium/High] ([calculated FPUs]). ADDITIONAL INSULIN: Consider [percentage]% extra insulin over [duration] hours for protein/fat. EXTENDED BOLUS: [specific recommendations for pump users]. MDI USERS: [split dosing recommendations]",
  "exercise_considerations": "PRE-EXERCISE: [specific guidance if meal within 6 hours of planned activity]. POST-EXERCISE: [recommendations if within 6 hours of recent exercise]. INSULIN ADJUSTMENTS: [specific percentage reductions if applicable]",
  "absorption_time_hours": hours_between_2_and_5,
  "absorption_time_reasoning": "IMPORTANT: Loop's default absorption time is 3 hours, which works well for most meals. Only recommend a DIFFERENT value when the meal composition clearly justifies it. Use CONSERVATIVE adjustments: FPU IMPACT: High FPU (>4) adds at most +1 hour, Medium FPU (2-4) adds at most +0.5 hours, Low FPU (<2) adds nothing. FIBER EFFECT: High fiber (>8g) adds at most +0.5 hours. MEAL SIZE: Large meals (>800 cal) add at most +0.5 hours. Most mixed meals should be 3–3.5 hours. Only meals that are exceptionally high in fat AND large should approach 4.5–5 hours. RECOMMENDED: [final hours with explanation of why it differs from 3 if it does].",
  "meal_size_impact": "MEAL SIZE: [Small <400 kcal / Medium 400-800 kcal / Large >800 kcal]. GASTRIC EMPTYING: [impact on absorption timing]. DOSING MODIFICATIONS: [specific adjustments for meal size effects]",
  "individualization_factors": "PATIENT FACTORS: [Consider age, pregnancy, illness, menstrual cycle, temperature effects]. TECHNOLOGY: [Pump vs MDI considerations]. PERSONAL PATTERNS: [Recommendations for tracking individual response]",
  "safety_alerts": "[Any specific safety considerations: dawn phenomenon, gastroparesis, pregnancy, alcohol, recent hypoglycemia, current hyperglycemia, illness, temperature extremes, etc.]",
  "visual_assessment_details": "FOR FOOD PHOTOS: [textures, colors, cooking evidence]. FOR MENU OR RECIPE ITEMS: Menu text shows [description from menu]. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "[describe plate size]. The food is arranged [describe arrangement]. The textures I observe are [specific textures]. The colors are [specific colors]. The cooking methods evident are [specific evidence]. Any utensils visible are [describe utensils]. The background shows [describe background].",
  "portion_assessment_method": "Provide a detailed but natural explanation of your measurement methodology. Describe how you determined plate size, what reference objects you used for scale, your process for measuring each food item, how you estimated weights from visual cues, and how you calculated USDA serving equivalents. Include your confidence level and what factors affected measurement accuracy. Write conversationally, not as a numbered list."
}

FOR MENU ITEMS:
{
  "image_type": "menu_item",
  "food_items": [
    {
      "name": "menu item name as written on menu",
      "portion_estimate": "CANNOT DETERMINE - menu text only, no actual food visible",
      "usda_serving_size": "standard USDA serving size for this food type (e.g., '3 oz for chicken breast', '1/2 cup for cooked rice')",
      "serving_multiplier": 1.0,
      "preparation_method": "method described on menu (if any)",
      "visual_cues": "NONE - menu text analysis only",
      "carbohydrates": number_in_grams_for_USDA_standard_serving,
      "calories": number_in_kcal_for_USDA_standard_serving,
      "fat": number_in_grams_for_USDA_standard_serving,
      "fiber": number_in_grams_for_USDA_standard_serving,
      "protein": number_in_grams_for_USDA_standard_serving,
      "assessment_notes": "ESTIMATE ONLY - Based on USDA standard serving size. Cannot assess actual portions without seeing prepared food on plate."
    }
  ],
  "total_food_portions": count_of_distinct_food_items,
  "total_usda_servings": sum_of_all_serving_multipliers,
  "total_carbohydrates": sum_of_all_carbs,
  "total_calories": sum_of_all_calories,
  "total_fat": sum_of_all_fat,
  "total_protein": sum_of_all_protein,
  "confidence": decimal_between_0_and_1,
  "fat_protein_units": "Calculate total FPUs = (total_fat + total_protein) ÷ 10. Provide the numerical result and classification (Low <2, Medium 2-4, High >4)",
  "net_carbs_adjustment": "Calculate adjusted carbs for insulin dosing: total_carbohydrates - (soluble_fiber × 0.75). Show calculation and final net carbs value",
  "diabetes_considerations": "Based on available information: [carb sources, glycemic index impact, and timing considerations]. GLYCEMIC INDEX: [specify if foods are low GI (<55), medium GI (56-69), or high GI (70+) and explain impact on blood sugar]. For insulin dosing, consider [relevant factors including absorption speed and peak timing].",
  "insulin_timing_recommendations": "MEAL TYPE: [Simple/Complex/High Fat-Protein]. PRE-MEAL INSULIN TIMING: [specific minutes before eating]. BOLUS STRATEGY: [immediate percentage]% now, [extended percentage]% over [duration] hours if applicable. MONITORING: Check BG at [specific times] post-meal",
  "fpu_dosing_guidance": "FPU LEVEL: [Low/Medium/High] ([calculated FPUs]). ADDITIONAL INSULIN: Consider [percentage]% extra insulin over [duration] hours for protein/fat. EXTENDED BOLUS: [specific recommendations for pump users]. MDI USERS: [split dosing recommendations]",
  "exercise_considerations": "PRE-EXERCISE: [specific guidance if meal within 6 hours of planned activity]. POST-EXERCISE: [recommendations if within 6 hours of recent exercise]. INSULIN ADJUSTMENTS: [specific percentage reductions if applicable]",
  "absorption_time_hours": hours_between_2_and_5,
  "absorption_time_reasoning": "IMPORTANT: Loop's default absorption time is 3 hours, which works well for most meals. Only recommend a DIFFERENT value when the meal composition clearly justifies it. Use CONSERVATIVE adjustments: FPU IMPACT: High FPU (>4) adds at most +1 hour, Medium FPU (2-4) adds at most +0.5 hours, Low FPU (<2) adds nothing. FIBER EFFECT: High fiber (>8g) adds at most +0.5 hours. MEAL SIZE: Large meals (>800 cal) add at most +0.5 hours. Most mixed meals should be 3–3.5 hours. Only meals that are exceptionally high in fat AND large should approach 4.5–5 hours. RECOMMENDED: [final hours with explanation of why it differs from 3 if it does].",
  "meal_size_impact": "MEAL SIZE: [Small <400 kcal / Medium 400-800 kcal / Large >800 kcal]. GASTRIC EMPTYING: [impact on absorption timing]. DOSING MODIFICATIONS: [specific adjustments for meal size effects]",
  "individualization_factors": "PATIENT FACTORS: [Consider age, pregnancy, illness, menstrual cycle, temperature effects]. TECHNOLOGY: [Pump vs MDI considerations]. PERSONAL PATTERNS: [Recommendations for tracking individual response]",
  "safety_alerts": "[Any specific safety considerations: dawn phenomenon, gastroparesis, pregnancy, alcohol, recent hypoglycemia, current hyperglycemia, illness, temperature extremes, etc.]",
  "visual_assessment_details": "FOR FOOD PHOTOS: [textures, colors, cooking evidence]. FOR MENU ITEMS: Menu text shows [description from menu]. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}

MENU ITEM EXAMPLE:
If menu shows "Grilled Chicken Caesar Salad", respond:
{
  "image_type": "menu_item",
  "food_items": [
    {
      "name": "Grilled Chicken Caesar Salad",
      "portion_estimate": "CANNOT DETERMINE - menu text only, no actual food visible",
      "usda_serving_size": "3 oz chicken breast + 2 cups mixed greens",
      "serving_multiplier": 1.0,
      "preparation_method": "grilled chicken as described on menu",
      "visual_cues": "NONE - menu text analysis only",
      "carbohydrates": 8.0,
      "calories": 250,
      "fat": 12.0,
      "fiber": 3.0,
      "protein": 25.0,
      "assessment_notes": "ESTIMATE ONLY - Based on USDA standard serving size. Cannot assess actual portions without seeing prepared food on plate."
    }
  ],
  "total_carbohydrates": 8.0,
  "total_calories": 250,
  "total_fat": 12.0,
  "total_fiber": 3.0,
  "total_protein": 25.0,
  "confidence": 0.7,
  "fat_protein_units": "FPUs = (12g fat + 25g protein) ÷ 10 = 3.7 FPUs. Classification: Medium-High FPU meal",
  "net_carbs_adjustment": "Net carbs = 8g total carbs - (3g fiber × 0.5) = 6.5g effective carbs for insulin dosing",
  "diabetes_considerations": "Based on menu analysis: Low glycemic impact due to minimal carbs from vegetables and croutons (estimated 8g total). Mixed meal with high protein (25g) and moderate fat (12g) will slow carb absorption. For insulin dosing, this is a low-carb meal requiring minimal rapid-acting insulin. Consider extended bolus if using insulin pump due to protein and fat content.",
  "insulin_timing_recommendations": "MEAL TYPE: High Fat-Protein. PRE-MEAL INSULIN TIMING: 5-10 minutes before eating. BOLUS STRATEGY: 50% now, 50% extended over 3-4 hours. MONITORING: Check BG at 2 hours and 4 hours post-meal",
  "fpu_dosing_guidance": "FPU LEVEL: Medium-High (3.7 FPUs). ADDITIONAL INSULIN: Consider 15-20% extra insulin over 3-4 hours for protein conversion. EXTENDED BOLUS: Use square wave 50%/50% over 3-4 hours. MDI USERS: Consider small additional injection at 2-3 hours post-meal",
  "exercise_considerations": "PRE-EXERCISE: Ideal pre-workout meal due to sustained energy from protein/fat. POST-EXERCISE: Good recovery meal if within 2 hours of exercise. INSULIN ADJUSTMENTS: Reduce insulin by 25-30% if recent exercise",
  "absorption_time_hours": 3,
  "absorption_time_reasoning": "Staying close to Loop's 3-hour default. FPU IMPACT: 3.7 FPUs (Medium) — fat/protein slow gastric emptying slightly (+0.5 hours) but don't dramatically extend carb absorption. FIBER EFFECT: Low fiber (3g) — no meaningful impact. MEAL SIZE: Small-medium (250 kcal) — no impact. With only 8g carbs, the carb absorption itself is fast, but the moderate fat/protein content warrants a small extension. RECOMMENDED: 3 hours — the carbs absorb quickly and the fat/protein create a minor secondary glucose effect that Loop handles through its prediction algorithm.",
  "meal_size_impact": "MEAL SIZE: Medium 250 kcal. GASTRIC EMPTYING: Normal rate expected due to moderate calories and liquid content. DOSING MODIFICATIONS: No size-related adjustments needed",
  "individualization_factors": "PATIENT FACTORS: Standard adult dosing applies unless pregnancy/illness present. TECHNOLOGY: Pump users can optimize with precise extended bolus; MDI users should consider split injection. PERSONAL PATTERNS: Track 4-hour post-meal glucose to optimize protein dosing",
  "safety_alerts": "Low carb content minimizes hypoglycemia risk. High protein may cause delayed glucose rise 3-5 hours post-meal - monitor extended.",
  "visual_assessment_details": "Menu text shows 'Grilled Chicken Caesar Salad'. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}

HIGH GLYCEMIC INDEX EXAMPLE:
If menu shows "Teriyaki Chicken Bowl with White Rice", respond:
{
  "image_type": "menu_item",
  "food_items": [
    {
      "name": "Teriyaki Chicken with White Rice",
      "portion_estimate": "CANNOT DETERMINE - menu text only, no actual food visible",
      "usda_serving_size": "3 oz chicken breast + 1/2 cup cooked white rice",
      "serving_multiplier": 1.0,
      "preparation_method": "teriyaki glazed chicken with steamed white rice as described on menu",
      "visual_cues": "NONE - menu text analysis only",
      "carbohydrates": 35.0,
      "calories": 320,
      "fat": 6.0,
      "fiber": 1.5,
      "protein": 28.0,
      "assessment_notes": "ESTIMATE ONLY - Based on USDA standard serving size. Cannot assess actual portions without seeing prepared food on plate."
    }
  ],
  "total_carbohydrates": 35.0,
  "total_calories": 320,
  "total_fat": 6.0,
  "total_fiber": 1.5,
  "total_protein": 28.0,
  "confidence": 0.7,
  "fat_protein_units": "FPUs = (6g fat + 28g protein) ÷ 10 = 3.4 FPUs. Classification: Medium FPU meal",
  "net_carbs_adjustment": "Net carbs = 35g total carbs - (1.5g fiber × 0.5) = 34.3g effective carbs for insulin dosing",
  "diabetes_considerations": "Based on menu analysis: HIGH GLYCEMIC INDEX meal due to white rice (GI ~73). The 35g carbs will cause rapid blood sugar spike within 15-30 minutes. However, protein (28g) and moderate fat (6g) provide significant moderation - mixed meal effect reduces overall glycemic impact compared to eating rice alone. For insulin dosing: Consider pre-meal rapid-acting insulin 10-15 minutes before eating (shorter timing due to protein/fat). Monitor for peak blood sugar at 45-75 minutes post-meal (delayed peak due to mixed meal). Teriyaki sauce adds sugars but protein helps buffer the response.",
  "insulin_timing_recommendations": "MEAL TYPE: Complex carbs with moderate protein. PRE-MEAL INSULIN TIMING: 10-15 minutes before eating. BOLUS STRATEGY: 70% now, 30% extended over 2-3 hours. MONITORING: Check BG at 1 hour and 3 hours post-meal",
  "fpu_dosing_guidance": "FPU LEVEL: Medium (3.4 FPUs). ADDITIONAL INSULIN: Consider 10-15% extra insulin over 2-3 hours for protein. EXTENDED BOLUS: Use dual wave 70%/30% over 2-3 hours. MDI USERS: Main bolus now, small follow-up at 2 hours if needed",
  "exercise_considerations": "PRE-EXERCISE: Good energy for cardio if consumed 1-2 hours before. POST-EXERCISE: Excellent recovery meal within 30 minutes. INSULIN ADJUSTMENTS: Reduce total insulin by 20-25% if recent exercise",
  "absorption_time_hours": 3.5,
  "absorption_time_reasoning": "Starting from Loop's 3-hour default. FPU IMPACT: 3.4 FPUs (Medium) — moderate fat/protein slows gastric emptying slightly (+0.5 hours). FIBER EFFECT: Low fiber (1.5g) — no meaningful impact. MEAL SIZE: Small-medium (320 kcal) — no impact. White rice is high-GI and absorbs quickly, but the protein content provides a small slowing effect. RECOMMENDED: 3.5 hours — a modest increase from the default to account for the mixed meal composition.",
  "safety_alerts": "High GI rice may cause rapid BG spike - monitor closely at 1 hour. Protein may extend glucose response beyond 3 hours.",
  "visual_assessment_details": "Menu text shows 'Teriyaki Chicken Bowl with White Rice'. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}

MIXED GI FOOD COMBINATION EXAMPLE:
If menu shows "Quinoa Bowl with Sweet Potato and Black Beans", respond:
{
  "image_type": "menu_item",
  "food_items": [
    {
      "name": "Quinoa Bowl with Sweet Potato and Black Beans",
      "portion_estimate": "CANNOT DETERMINE - menu text only, no actual food visible",
      "usda_serving_size": "1/2 cup cooked quinoa + 1/2 cup sweet potato + 1/2 cup black beans",
      "serving_multiplier": 1.0,
      "preparation_method": "cooked quinoa, roasted sweet potato, and seasoned black beans as described on menu",
      "visual_cues": "NONE - menu text analysis only",
      "carbohydrates": 42.0,
      "calories": 285,
      "fat": 4.0,
      "fiber": 8.5,
      "protein": 12.0,
      "assessment_notes": "ESTIMATE ONLY - Based on USDA standard serving size. Cannot assess actual portions without seeing prepared food on plate."
    }
  ],
  "total_carbohydrates": 42.0,
  "total_calories": 285,
  "total_fat": 4.0,
  "total_fiber": 8.5,
  "total_protein": 12.0,
  "confidence": 0.8,
  "fat_protein_units": "FPUs = (4g fat + 12g protein) ÷ 10 = 1.6 FPUs. Classification: Low FPU meal",
  "net_carbs_adjustment": "Net carbs = 42g total carbs - (8.5g fiber × 0.75) = 35.6g effective carbs for insulin dosing (significant fiber reduction)",
  "diabetes_considerations": "Based on menu analysis: MIXED GLYCEMIC INDEX meal with balanced components. Quinoa (low-medium GI ~53), sweet potato (medium GI ~54), and black beans (low GI ~30) create favorable combination. High fiber content (estimated 8.5g+) and plant protein (12g) significantly slow carb absorption. For insulin dosing: This meal allows 20-30 minute pre-meal insulin timing due to low-medium GI foods and high fiber. Expect gradual, sustained blood sugar rise over 60-120 minutes rather than sharp spike. Ideal for extended insulin action.",
  "insulin_timing_recommendations": "MEAL TYPE: Complex carbs with high fiber. PRE-MEAL INSULIN TIMING: 20-25 minutes before eating. BOLUS STRATEGY: 80% now, 20% extended over 2 hours. MONITORING: Check BG at 2 hours post-meal",
  "fpu_dosing_guidance": "FPU LEVEL: Low (1.6 FPUs). ADDITIONAL INSULIN: Minimal extra needed for protein/fat. EXTENDED BOLUS: Use slight tail 80%/20% over 2 hours. MDI USERS: Single injection should suffice",
  "exercise_considerations": "PRE-EXERCISE: Excellent sustained energy meal for endurance activities. POST-EXERCISE: Good recovery with complex carbs and plant protein. INSULIN ADJUSTMENTS: Reduce insulin by 15-20% if recent exercise",
  "absorption_time_hours": 3.5,
  "absorption_time_reasoning": "Starting from Loop's 3-hour default. FPU IMPACT: 1.6 FPUs (Low) — minimal fat/protein, no meaningful extension. FIBER EFFECT: High fiber (8.5g) slows carb absorption modestly (+0.5 hours). MEAL SIZE: Small-medium (285 kcal) — no impact. While the high fiber and complex carbs (quinoa, sweet potato, beans) slow the glucose rise, this primarily affects the *shape* of the curve (flatter, more gradual) rather than dramatically extending total absorption duration. RECOMMENDED: 3.5 hours — a modest increase from default to account for the high fiber content slowing gastric emptying.",
  "safety_alerts": "High fiber significantly blunts glucose response - avoid over-dosing insulin. Gradual rise may delay hypoglycemia symptoms.",
  "visual_assessment_details": "Menu text shows 'Quinoa Bowl with Sweet Potato and Black Beans'. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}
"""

/// Individual food item analysis with detailed portion assessment
struct FoodItemAnalysis: Codable, Equatable {
    let name: String
    let portionEstimate: String
    let usdaServingSize: String?
    let servingMultiplier: Double
    let preparationMethod: String?
    let visualCues: String?
    let carbohydrates: Double
    let calories: Double?
    let fat: Double?
    let fiber: Double?
    let protein: Double?
    let assessmentNotes: String?
    // Optional per-item absorption time (hours) if provided by the AI
    let absorptionTimeHours: Double?
}

/// Type of image being analyzed
enum ImageAnalysisType: String, Codable {
    case foodPhoto = "food_photo"
    case menuItem = "menu_item"
}

/// Result from AI food analysis with detailed breakdown
struct AIFoodAnalysisResult: Codable, Equatable {
    let imageType: ImageAnalysisType?
    var foodItemsDetailed: [FoodItemAnalysis]
    let overallDescription: String?
    let confidence: AIConfidenceLevel
    let numericConfidence: Double?
    let totalFoodPortions: Int?
    let totalUsdaServings: Double?
    var totalCarbohydrates: Double
    var totalProtein: Double?
    var totalFat: Double?
    var totalFiber: Double?
    var totalCalories: Double?
    let portionAssessmentMethod: String?
    let diabetesConsiderations: String?
    let visualAssessmentDetails: String?
    let notes: String?
    
    // Store original baseline servings for proper scaling calculations
    let originalServings: Double
    
    // Advanced dosing fields (optional for backward compatibility)
    let fatProteinUnits: String?
    let netCarbsAdjustment: String?
    let insulinTimingRecommendations: String?
    let fpuDosingGuidance: String?
    let exerciseConsiderations: String?
    var absorptionTimeHours: Double?
    var absorptionTimeReasoning: String?
    let mealSizeImpact: String?
    let individualizationFactors: String?
    let safetyAlerts: String?
    
    // Legacy compatibility properties
    var foodItems: [String] {
        return foodItemsDetailed.map { $0.name }
    }
    
    var detailedDescription: String? {
        return overallDescription
    }
    
    var portionSize: String {
        if foodItemsDetailed.count == 1 {
            return foodItemsDetailed.first?.portionEstimate ?? "1 serving"
        } else {
            // Create concise food summary for multiple items (clean food names)
            let foodNames = foodItemsDetailed.map { item in
                // Clean up food names by removing technical terms
                cleanFoodName(item.name)
            }
            return foodNames.joined(separator: ", ")
        }
    }
    
    // Helper function to clean food names for display
    private func cleanFoodName(_ name: String) -> String {
        var cleaned = name
        
        // Remove common technical terms while preserving essential info
        let removals = [
            " Breast", " Fillet", " Thigh", " Florets", " Spears",
            " Cubes", " Medley", " Portion"
        ]
        
        for removal in removals {
            cleaned = cleaned.replacingOccurrences(of: removal, with: "")
        }
        
        // Capitalize first letter and trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        
        return cleaned.isEmpty ? name : cleaned
    }
    
    var servingSizeDescription: String {
        if foodItemsDetailed.count == 1 {
            return foodItemsDetailed.first?.portionEstimate ?? "1 serving"
        } else {
            // Return the same clean food names for "Based on" text
            let foodNames = foodItemsDetailed.map { item in
                cleanFoodName(item.name)
            }
            return foodNames.joined(separator: ", ")
        }
    }
    
    var carbohydrates: Double {
        return totalCarbohydrates
    }
    
    var protein: Double? {
        return totalProtein
    }
    
    var fat: Double? {
        return totalFat
    }
    
    var calories: Double? {
        return totalCalories
    }
    
    var fiber: Double? {
        return totalFiber
    }
    
    var servings: Double {
        return foodItemsDetailed.reduce(0) { $0 + $1.servingMultiplier }
    }
    
    var analysisNotes: String? {
        return portionAssessmentMethod
    }
}

/// Confidence level for AI analysis
enum AIConfidenceLevel: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium" 
    case low = "low"
}

/// Errors that can occur during AI food analysis
enum AIFoodAnalysisError: Error, LocalizedError {
    case imageProcessingFailed
    case requestCreationFailed
    case networkError(Error)
    case invalidResponse
    case invalidResponseFormat
    case apiError(Int)
    case apiErrorWithMessage(statusCode: Int, message: String)
    case responseParsingFailed
    case noApiKey
    case customError(String)
    case configurationError(String)
    case creditsExhausted(provider: String)
    case rateLimitExceeded(provider: String)
    case rateLimitExceededGeneric
    case quotaExceeded(provider: String)
    case insufficientQuota
    case timeout
    case invalidModel
    case invalidURL(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return NSLocalizedString("Failed to process image for analysis", comment: "Error when image processing fails")
        case .requestCreationFailed:
            return NSLocalizedString("Failed to create analysis request", comment: "Error when request creation fails")
        case .networkError(let error):
            return String(format: NSLocalizedString("Network error: %@", comment: "Error for network failures"), error.localizedDescription)
        case .invalidResponse:
            return NSLocalizedString("Invalid response from AI service", comment: "Error for invalid API response")
        case .invalidResponseFormat:
            return NSLocalizedString("Invalid response format from AI service", comment: "Error for invalid response format")
        case .apiError(let code):
            if code == 400 {
                return NSLocalizedString("Invalid API request (400). Please check your API key configuration in FoodFinder Settings.", comment: "Error for 400 API failures")
            } else if code == 403 {
                return NSLocalizedString("API access forbidden (403). Your API key may be invalid or you've exceeded your quota.", comment: "Error for 403 API failures")
            } else if code == 404 {
                return NSLocalizedString("AI service not found (404). Please check your API configuration.", comment: "Error for 404 API failures")
            } else {
                return String(format: NSLocalizedString("AI service error (code: %d)", comment: "Error for API failures"), code)
            }
        case .apiErrorWithMessage(statusCode: let code, message: let message):
            return String(format: NSLocalizedString("AI service error (code: %d): %@", comment: "Error for API failures with message"), code, message)
        case .responseParsingFailed:
            return NSLocalizedString("Failed to parse AI analysis results", comment: "Error when response parsing fails")
        case .noApiKey:
            return NSLocalizedString("No API key configured. Please go to FoodFinder Settings to set up your API key.", comment: "Error when API key is missing")
        case .customError(let message):
            return message
        case .configurationError(let message):
            return String(format: NSLocalizedString("Configuration error: %@", comment: "Error for configuration issues"), message)
        case .creditsExhausted(let provider):
            return String(format: NSLocalizedString("%@ credits exhausted. Please check your account billing or add credits to continue using AI food analysis.", comment: "Error when AI provider credits are exhausted"), provider)
        case .rateLimitExceeded(let provider):
            return String(format: NSLocalizedString("%@ rate limit exceeded. Please wait a moment before trying again.", comment: "Error when AI provider rate limit is exceeded"), provider)
        case .rateLimitExceededGeneric:
            return NSLocalizedString("Rate limit exceeded. Please wait a moment before trying again.", comment: "Error when rate limit is exceeded")
        case .quotaExceeded(let provider):
            return String(format: NSLocalizedString("%@ quota exceeded. Please check your usage limits or upgrade your plan.", comment: "Error when AI provider quota is exceeded"), provider)
        case .insufficientQuota:
            return NSLocalizedString("Insufficient quota. Please check your usage limits or upgrade your plan.", comment: "Error when quota is insufficient")
        case .timeout:
            return NSLocalizedString("Analysis timed out. Please check your network connection and try again.", comment: "Error when AI analysis times out")
        case .invalidModel:
            return NSLocalizedString("Invalid or unsupported model specified. Please check your AI configuration.", comment: "Error when model is invalid")
        case .invalidURL(let url):
            return String(format: NSLocalizedString("Invalid URL: %@", comment: "Error for invalid URL"), url)
        case .serverError(let message):
            return String(format: NSLocalizedString("Server error: %@", comment: "Error for server failures"), message)
        }
    }
}

// MARK: - Search Types

/// Different types of food searches that can use different providers
enum SearchType: String, CaseIterable {
    case textSearch = "Text/Voice Search"
    case barcodeSearch = "Barcode Scanning"
    case aiImageSearch = "AI Image Analysis"
    
    var description: String {
        switch self {
        case .textSearch:
            return "Search by typing food names or using voice input"
        case .barcodeSearch:
            return "Scan product barcodes with camera"
        case .aiImageSearch:
            return "Take photos of food for AI analysis"
        }
    }
}

/// Available providers for different search types
enum SearchProvider: String, CaseIterable {
    case aiProvider = "AI Provider"
    case openFoodFacts = "OpenFoodFacts (Default)"
    case usdaFoodData = "USDA FoodData Central"

    var supportsSearchType: [SearchType] {
        switch self {
        case .aiProvider:
            return [.textSearch, .aiImageSearch]
        case .openFoodFacts:
            return [.textSearch, .barcodeSearch]
        case .usdaFoodData:
            return [.textSearch]
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openFoodFacts, .usdaFoodData:
            return false
        case .aiProvider:
            return true
        }
    }
}

// MARK: - Confidence Extraction (file-scope helper)

/// Attempts to extract a numeric confidence score (0.0–1.0) from provider JSON.
/// Accepts numeric values or common string variants such as "high", "medium", etc.
private func extractNumericConfidence(from json: [String: Any]) -> Double? {
    let keys = ["confidence", "confidence_score", "accuracy", "confidence_level"]
    for key in keys {
        if let d = json[key] as? Double { return min(1.0, max(0.0, d)) }
        if let s = json[key] as? String {
            let ls = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let v = Double(ls) { return min(1.0, max(0.0, v)) }
            switch ls {
            case "very high": return 0.9
            case "high": return 0.85
            case "medium", "moderate": return 0.65
            case "low", "very low": return 0.4
            default: break
            }
        }
    }
    return nil
}

// MARK: - Intelligent Caching System

/// Cache for AI analysis results based on image hashing
class ImageAnalysisCache {
    private let cache = NSCache<NSString, CachedAnalysisResult>()
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    
    init() {
        // Configure cache limits
        cache.countLimit = 50  // Maximum 50 cached results
        cache.totalCostLimit = 10 * 1024 * 1024  // 10MB limit
    }
    
    /// Cache an analysis result for the given image
    func cacheResult(_ result: AIFoodAnalysisResult, for image: UIImage) {
        let imageHash = calculateImageHash(image)
        let cachedResult = CachedAnalysisResult(
            result: result,
            timestamp: Date(),
            imageHash: imageHash
        )
        // Estimate object cost in bytes for effective totalCostLimit behavior
        let cost = estimateCostBytes(for: result)
        cache.setObject(cachedResult, forKey: imageHash as NSString, cost: cost)
    }
    
    /// Get cached result for the given image if available and not expired
    func getCachedResult(for image: UIImage) -> AIFoodAnalysisResult? {
        let imageHash = calculateImageHash(image)
        
        guard let cachedResult = cache.object(forKey: imageHash as NSString) else {
            return nil
        }
        
        // Check if cache entry has expired
        if Date().timeIntervalSince(cachedResult.timestamp) > cacheExpirationTime {
            cache.removeObject(forKey: imageHash as NSString)
            return nil
        }
        
        return cachedResult.result
    }
    
    /// Calculate a hash for the image to use as cache key
    private func calculateImageHash(_ image: UIImage) -> String {
        // Convert image to data and calculate SHA256 hash
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return UUID().uuidString
        }
        
        let hash = imageData.sha256Hash
        return hash
    }
    
    /// Clear all cached results
    func clearCache() {
        cache.removeAllObjects()
    }

    /// Approximate serialized byte size of a result for NSCache cost
    private func estimateCostBytes(for result: AIFoodAnalysisResult) -> Int {
        var bytes = 0
        // String fields
        func addString(_ s: String?) { if let s = s { bytes += s.utf8.count } }
        addString(result.overallDescription)
        addString(result.portionAssessmentMethod)
        addString(result.diabetesConsiderations)
        addString(result.visualAssessmentDetails)
        addString(result.notes)
        addString(result.absorptionTimeReasoning)
        addString(result.mealSizeImpact)
        addString(result.individualizationFactors)
        addString(result.safetyAlerts)
        addString(result.fatProteinUnits)
        addString(result.netCarbsAdjustment)
        addString(result.insulinTimingRecommendations)
        addString(result.fpuDosingGuidance)
        addString(result.exerciseConsiderations)
        // Numbers (8 bytes each as approximation)
        func addNum(_ n: Double?) { if n != nil { bytes += 8 } }
        addNum(result.totalProtein)
        addNum(result.totalFat)
        addNum(result.totalFiber)
        addNum(result.totalCalories)
        addNum(result.absorptionTimeHours)
        // Detailed items
        for item in result.foodItemsDetailed {
            addString(item.name)
            addString(item.portionEstimate)
            addString(item.usdaServingSize)
            addString(item.preparationMethod)
            addString(item.visualCues)
            addString(item.assessmentNotes)
            addNum(item.calories)
            addNum(item.fat)
            addNum(item.fiber)
            addNum(item.protein)
            bytes += 8 // carbs
            bytes += 8 // servingMultiplier
            addNum(item.absorptionTimeHours)
        }
        // Base overhead
        return max(bytes, 1024)
    }
}

extension ImageAnalysisCache {
    /// Cache using a preencoded image + provider key (prevents cross‑provider collisions)
    func cacheResult(_ result: AIFoodAnalysisResult, forPreencoded pre: PreencodedImage, providerKey: String) {
        let key = (pre.sha256 + "|" + providerKey) as NSString
        let cached = CachedAnalysisResult(result: result, timestamp: Date(), imageHash: pre.sha256)
        let cost = estimateCostBytes(for: result)
        cache.setObject(cached, forKey: key, cost: cost)
    }

    /// Retrieve cache using a preencoded image key + provider key
    func getCachedResult(forPreencoded pre: PreencodedImage, providerKey: String) -> AIFoodAnalysisResult? {
        let key = (pre.sha256 + "|" + providerKey) as NSString
        guard let cached = cache.object(forKey: key) else { return nil }
        if Date().timeIntervalSince(cached.timestamp) > cacheExpirationTime {
            cache.removeObject(forKey: key)
            return nil
        }
        return cached.result
    }
}

/// Wrapper for cached analysis results with metadata
private class CachedAnalysisResult {
    let result: AIFoodAnalysisResult
    let timestamp: Date
    let imageHash: String
    
    init(result: AIFoodAnalysisResult, timestamp: Date, imageHash: String) {
        self.result = result
        self.timestamp = timestamp
        self.imageHash = imageHash
    }
}

/// Extension to calculate SHA256 hash for Data
extension Data {
    var sha256Hash: String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Configurable AI Service

/// AI service that routes through the user's configured BYO endpoint.
class ConfigurableAIService: ObservableObject {

    // MARK: - Singleton

    static let shared = ConfigurableAIService()

    // MARK: - Published Properties

    @Published var textSearchProvider: SearchProvider = .openFoodFacts
    @Published var barcodeSearchProvider: SearchProvider = .openFoodFacts
    @Published var aiImageSearchProvider: SearchProvider = .aiProvider

    private init() {
        // Text and barcode search use database providers.
        // AI image analysis uses the configured BYO provider.
    }

    // MARK: - Configuration

    /// Whether the AI provider is configured (has an API key in Keychain).
    var isConfigured: Bool {
        let key = FoodFinder_SecureStorage.loadAPIKey() ?? ""
        return !key.isEmpty
    }

    // MARK: - Search Type Configuration

    func getProviderForSearchType(_ searchType: SearchType) -> SearchProvider {
        switch searchType {
        case .textSearch: return textSearchProvider
        case .barcodeSearch: return barcodeSearchProvider
        case .aiImageSearch: return .aiProvider
        }
    }

    func setProviderForSearchType(_ provider: SearchProvider, searchType: SearchType) {
        switch searchType {
        case .textSearch:
            textSearchProvider = provider
        case .barcodeSearch:
            barcodeSearchProvider = provider
        case .aiImageSearch:
            aiImageSearchProvider = provider
        }
    }

    func getAvailableProvidersForSearchType(_ searchType: SearchType) -> [SearchProvider] {
        return SearchProvider.allCases
            .filter { $0.supportsSearchType.contains(searchType) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// Get a summary of current provider configuration
    func getProviderConfigurationSummary() -> String {
        let textProvider = getProviderForSearchType(.textSearch).rawValue
        let barcodeProvider = getProviderForSearchType(.barcodeSearch).rawValue
        let aiProvider = getProviderForSearchType(.aiImageSearch).rawValue

        return """
        Search Configuration:
        • Text/Voice: \(textProvider)
        • Barcode: \(barcodeProvider)
        • AI Image: \(aiProvider)
        """
    }

    // MARK: - AI Analysis

    /// Intelligent caching system for AI analysis results
    private var imageAnalysisCache = ImageAnalysisCache()

    /// Analyze food image using the configured BYO provider with intelligent caching.
    func analyzeFoodImage(_ image: UIImage) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, telemetryCallback: nil)
    }

    /// Analyze food image with telemetry callbacks for progress tracking.
    /// Runs on-device OCR first — if a menu/recipe/text is detected, routes through
    /// the text analysis path (same as voice dictation) for much better results.
    func analyzeFoodImage(_ image: UIImage, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        guard let config = UserDefaults.standard.activeAIProviderConfiguration else {
            throw AIFoodAnalysisError.noApiKey
        }
        guard !config.apiKey.isEmpty else {
            throw AIFoodAnalysisError.noApiKey
        }

        // ── Step 1: On-device OCR to detect menus, recipes, or text ──
        telemetryCallback?("🔍 Scanning image for text...")
        let ocr = await ConfigurableAIService.performOCR(on: image)

        if ocr.isMenuOrRecipe {
            #if DEBUG
            print("📝 [OCR] Menu/recipe detected: \(ocr.lineCount) lines, confidence \(String(format: "%.0f%%", ocr.averageConfidence * 100))")
            print("📝 [OCR] Extracted text:\n\(ocr.text.prefix(500))")
            #endif

            telemetryCallback?("📝 Menu/recipe detected (\(ocr.lineCount) text lines)")
            telemetryCallback?("🤖 Analyzing menu text with \(config.name)...")

            let basePrompt = getAnalysisPrompt()
            let menuPrompt = """
            \(basePrompt)

            The following text was extracted via OCR from a photo of a menu, recipe, or food label. \
            Analyze these food items and provide detailed nutritional information. \
            Set "image_type" to "menu_item". \
            If the text is in a foreign language, translate the food item names to English before analysis.

            OCR-extracted text:
            \"""
            \(ocr.text)
            \"""
            """

            // Always include the image alongside OCR text so the AI has
            // full visual context. This prevents catastrophic failure if OCR
            // misclassifies a food photo as a menu — the AI can still see the
            // actual food and analyze it correctly.
            let result = try await AIServiceManager.shared.analyzeFoodImage(
                image,
                using: config,
                query: menuPrompt
            )

            telemetryCallback?("✅ Menu analysis complete!")
            return result
        }

        #if DEBUG
        if !ocr.text.isEmpty {
            print("📝 [OCR] Some text found but not enough for menu detection: \(ocr.lineCount) lines, confidence \(String(format: "%.0f%%", ocr.averageConfidence * 100))")
        }
        #endif

        // ── Step 2: Normal image analysis path (food photo) ──
        telemetryCallback?("🖼️ Preparing image...")
        let pre = await ConfigurableAIService.preencodeImageForProviders(image)

        let originalWidth = Int((image.size.width * image.scale).rounded())
        let originalHeight = Int((image.size.height * image.scale).rounded())
        if pre.width > 0, pre.height > 0,
           (pre.width != originalWidth || pre.height != originalHeight) {
            telemetryCallback?("✂️ Optimized to \(pre.width)×\(pre.height) px (was \(originalWidth)×\(originalHeight))")
        }
        telemetryCallback?(String(format: "🗜️ Encoded ≈ %.0f KB", Double(pre.bytes) / 1024.0))

        // Cache key based on provider config
        let advFlag = UserDefaults.standard.advancedDosingRecommendationsEnabled ? "adv" : "std"
        let cacheKey = [config.name, config.model, config.baseURL, advFlag].joined(separator: "|")

        if let cached = imageAnalysisCache.getCachedResult(forPreencoded: pre, providerKey: cacheKey) {
            telemetryCallback?("⚡ Using cached analysis result")
            return cached
        }

        telemetryCallback?("🤖 Connecting to \(config.name)...")

        let prompt = getAnalysisPrompt()
        let result = try await AIServiceManager.shared.analyzeFoodImage(
            pre.resizedImage,
            using: config,
            query: prompt
        )

        telemetryCallback?("💾 Caching analysis result...")
        imageAnalysisCache.cacheResult(result, forPreencoded: pre, providerKey: cacheKey)

        return result
    }

    // MARK: - Text Processing Helper Methods

    /// Centralized list of unwanted prefixes that AI commonly adds to food descriptions
    /// Add new prefixes here as edge cases are discovered - this is the SINGLE source of truth
    static let unwantedFoodPrefixes = [
        "of ",
        "with ",
        "contains ",
        "includes ",
        "featuring ",
        "consisting of ",
        "made of ",
        "composed of ",
        "a plate of ",
        "a bowl of ",
        "a serving of ",
        "a portion of ",
        "some ",
        "several ",
        "multiple ",
        "various ",
        "an ",
        "a ",
        "the ",
        "- ",
        "– ",
        "— ",
        "this is ",
        "there is ",
        "there are ",
        "i see ",
        "appears to be ",
        "looks like "
    ]

    /// Adaptive image compression based on image size for optimal performance
    static func adaptiveCompressionQuality(for image: UIImage) -> CGFloat {
        let imagePixels = image.size.width * image.size.height

        // Adaptive compression: larger images need more compression for faster uploads
        switch imagePixels {
        case 0..<500_000:      // Small images (< 500k pixels)
            return 0.9
        case 500_000..<1_000_000: // Medium images (500k-1M pixels)
            return 0.8
        default:               // Large images (> 1M pixels)
            return 0.7
        }
    }

    /// Provider-specific optimized timeouts for better performance and user experience
    static func optimalTimeout(for provider: SearchProvider) -> TimeInterval {
        switch provider {
        case .aiProvider:
            return 30  // Reasonable default for any AI provider
        case .openFoodFacts, .usdaFoodData:
            return 10  // Simple API calls should be fast
        }
    }

    /// Safe async image optimization to prevent main thread blocking
    static func optimizeImageForAnalysisSafely(_ image: UIImage) async -> UIImage {
        return await withCheckedContinuation { continuation in
            // Process image on background thread to prevent UI freezing
            DispatchQueue.global(qos: .userInitiated).async {
                let optimized = optimizeImageForAnalysis(image)
                continuation.resume(returning: optimized)
            }
        }
    }

    /// Intelligent image resizing for optimal AI analysis performance
    static func optimizeImageForAnalysis(_ image: UIImage) -> UIImage {
        let trimmed = cropUniformBorder(from: image)
        let maxDimension: CGFloat = 1024

        if trimmed.size.width <= maxDimension && trimmed.size.height <= maxDimension {
            return trimmed
        }

        let scale = maxDimension / max(trimmed.size.width, trimmed.size.height)
        let newSize = CGSize(width: trimmed.size.width * scale,
                             height: trimmed.size.height * scale)

        return resizeImage(trimmed, to: newSize)
    }

    /// Pre-encode an image once for all providers with a byte budget
    /// - Parameters:
    ///   - image: source image
    ///   - targetBytes: desired upper bound in bytes (default ~450 KB)
    /// - Returns: PreencodedImage with JPEG data, base64, and SHA256
    static func preencodeImageForProviders(_ image: UIImage, targetBytes: Int = 450 * 1024) async -> PreencodedImage {
        // Respect user cancellation before heavy work
        try? Task.checkCancellation()
        let optimized = await optimizeImageForAnalysisSafely(image)
        try? Task.checkCancellation()
        let byteBudget = targetBytes
        // Binary search JPEG quality
        var low: CGFloat = 0.35
        var high: CGFloat = 0.95
        var bestData: Data? = nil
        for _ in 0..<7 { // ~7 iters is enough
            if Task.isCancelled { break }
            let mid = (low + high) / 2
            if let d = optimized.jpegData(compressionQuality: mid) {
                if d.count > byteBudget {
                    high = mid
                } else {
                    bestData = d
                    low = mid
                }
            } else {
                break
            }
        }
        var finalImage = optimized
        var data = bestData ?? (optimized.jpegData(compressionQuality: 0.75) ?? Data())
        // If still above target, downscale once and retry quickly at a safe quality
        if data.count > byteBudget {
            try? Task.checkCancellation()
            let scale: CGFloat = 0.85
            let newSize = CGSize(width: optimized.size.width * scale, height: optimized.size.height * scale)
            let downsized = resizeImage(optimized, to: newSize)
            finalImage = downsized
            data = downsized.jpegData(compressionQuality: 0.7) ?? data
        }
        let base64 = data.base64EncodedString()
        let sha = data.sha256Hash
        return PreencodedImage(
            resizedImage: finalImage,
            jpegData: data,
            base64: base64,
            sha256: sha,
            bytes: data.count,
            width: Int(finalImage.size.width),
            height: Int(finalImage.size.height)
        )
    }

    // MARK: - On-Device OCR for Menu/Recipe Detection

    /// Result of on-device OCR text detection
    struct OCRResult {
        let text: String
        let lineCount: Int
        let averageConfidence: Float
        let isMenuOrRecipe: Bool
    }

    /// Performs on-device OCR using Apple Vision to detect and extract text from an image.
    /// Runs on the full-resolution image for maximum accuracy — no compression or resizing.
    /// Returns extracted text and a flag indicating whether the image appears to be a menu/recipe.
    static func performOCR(on image: UIImage) async -> OCRResult {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: OCRResult(text: "", lineCount: 0, averageConfidence: 0, isMenuOrRecipe: false))
                return
            }

            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    continuation.resume(returning: OCRResult(text: "", lineCount: 0, averageConfidence: 0, isMenuOrRecipe: false))
                    return
                }

                var lines: [(String, Float)] = []
                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        lines.append((candidate.string, candidate.confidence))
                    }
                }

                let allText = lines.map { $0.0 }.joined(separator: "\n")
                let avgConfidence = lines.isEmpty ? 0 : lines.map { $0.1 }.reduce(0, +) / Float(lines.count)

                // Heuristic: treat as text-heavy image (menu/recipe) ONLY when
                // there is strong OCR evidence. Thresholds must be strict because
                // food photos often contain incidental text (packaging, labels,
                // brand names on cutting boards) and a false positive here means
                // the image is sent alongside the OCR text to the AI — we always
                // include the image now, but the prompt framing changes.
                //
                // A real menu/recipe typically has 5+ lines of readable text at
                // high confidence. A food photo with a brand label might have 1-2.
                let significantLines = lines.filter { $0.1 >= 0.5 }
                let isMenu = (significantLines.count >= 5 && allText.count >= 40 && avgConfidence >= 0.7)
                    || (significantLines.count >= 8 && avgConfidence >= 0.5)

                continuation.resume(returning: OCRResult(
                    text: allText,
                    lineCount: significantLines.count,
                    averageConfidence: avgConfidence,
                    isMenuOrRecipe: isMenu
                ))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: OCRResult(text: "", lineCount: 0, averageConfidence: 0, isMenuOrRecipe: false))
            }
        }
    }

    /// High-quality image resizing helper
    private static func resizeImage(_ image: UIImage, to newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    private static func cropUniformBorder(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 32, height > 32 else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: Int(bytesPerRow * height))

        guard let context = CGContext(data: &rawData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return image
        }

        // Ensure row 0 maps to the top edge
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        @inline(__always)
        func pixelOffset(x: Int, y: Int) -> Int {
            y * bytesPerRow + x * bytesPerPixel
        }

        @inline(__always)
        func sampleRGB(x: Int, y: Int) -> (Double, Double, Double) {
            let offset = pixelOffset(x: x, y: y)
            let r = Double(rawData[offset]) / 255.0
            let g = Double(rawData[offset + 1]) / 255.0
            let b = Double(rawData[offset + 2]) / 255.0
            return (r, g, b)
        }

        // Derive background color from corners and mid-edges
        let samplePoints: [(Int, Int)] = [
            (0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1),
            (width / 2, 0), (width / 2, height - 1), (0, height / 2), (width - 1, height / 2)
        ]
        var bgR = 0.0, bgG = 0.0, bgB = 0.0
        for point in samplePoints {
            let (r, g, b) = sampleRGB(x: max(0, min(width - 1, point.0)),
                                      y: max(0, min(height - 1, point.1)))
            bgR += r
            bgG += g
            bgB += b
        }
        let sampleCount = Double(samplePoints.count)
        bgR /= sampleCount
        bgG /= sampleCount
        bgB /= sampleCount

        let tolerance = 0.08
        @inline(__always)
        func isBackground(_ color: (Double, Double, Double)) -> Bool {
            let dr = abs(color.0 - bgR)
            let dg = abs(color.1 - bgG)
            let db = abs(color.2 - bgB)
            return dr < tolerance && dg < tolerance && db < tolerance
        }

        let sampleStride = max(1, min(width, height) / 300)
        var edgeSamples = 0
        var edgeMatches = 0

        func countEdgeMatches(xRange: StrideThrough<Int>, fixedY: Int) {
            for x in xRange {
                let rgb = sampleRGB(x: x, y: fixedY)
                if isBackground(rgb) { edgeMatches += 1 }
                edgeSamples += 1
            }
        }

        func countEdgeMatchesVertical(yRange: StrideThrough<Int>, fixedX: Int) {
            for y in yRange {
                let rgb = sampleRGB(x: fixedX, y: y)
                if isBackground(rgb) { edgeMatches += 1 }
                edgeSamples += 1
            }
        }

        let horizontalRange = stride(from: 0, through: width - 1, by: sampleStride)
        let verticalRange = stride(from: 0, through: height - 1, by: sampleStride)
        countEdgeMatches(xRange: horizontalRange, fixedY: 0)
        countEdgeMatches(xRange: horizontalRange, fixedY: height - 1)
        countEdgeMatchesVertical(yRange: verticalRange, fixedX: 0)
        countEdgeMatchesVertical(yRange: verticalRange, fixedX: width - 1)

        if edgeSamples == 0 || Double(edgeMatches) / Double(edgeSamples) < 0.65 {
            return image
        }

        func rowHasContent(_ y: Int) -> Bool {
            var nonBackground = 0
            var total = 0
            for x in stride(from: 0, to: width, by: sampleStride) {
                let rgb = sampleRGB(x: x, y: y)
                if !isBackground(rgb) { nonBackground += 1 }
                total += 1
                if nonBackground > max(1, total / 12) { return true }
            }
            return false
        }

        func columnHasContent(_ x: Int) -> Bool {
            var nonBackground = 0
            var total = 0
            for y in stride(from: 0, to: height, by: sampleStride) {
                let rgb = sampleRGB(x: x, y: y)
                if !isBackground(rgb) { nonBackground += 1 }
                total += 1
                if nonBackground > max(1, total / 12) { return true }
            }
            return false
        }

        var top = 0
        while top < height && !rowHasContent(top) {
            top += sampleStride
        }

        var bottom = height - 1
        while bottom > top && !rowHasContent(bottom) {
            bottom -= sampleStride
        }

        var left = 0
        while left < width && !columnHasContent(left) {
            left += sampleStride
        }

        var right = width - 1
        while right > left && !columnHasContent(right) {
            right -= sampleStride
        }

        if top <= 0 && left <= 0 && bottom >= height - 1 && right >= width - 1 {
            return image
        }

        let margin = max(sampleStride, Int(Double(min(width, height)) * 0.02))
        top = max(0, top - margin)
        left = max(0, left - margin)
        bottom = min(height - 1, bottom + margin)
        right = min(width - 1, right + margin)

        let cropWidth = right - left + 1
        let cropHeight = bottom - top + 1
        guard cropWidth > 0, cropHeight > 0 else { return image }

        let cropRect = CGRect(x: left, y: top, width: cropWidth, height: cropHeight)
        guard let cropped = cgImage.cropping(to: cropRect) else { return image }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Public static method to clean food text - can be called from anywhere
    static func cleanFoodText(_ text: String?) -> String? {
        guard let text = text else { return nil }

        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)


        // Keep removing prefixes until none match (handles multiple prefixes)
        var foundPrefix = true
        var iterationCount = 0
        while foundPrefix && iterationCount < 10 { // Prevent infinite loops
            foundPrefix = false
            iterationCount += 1

            for prefix in unwantedFoodPrefixes {
                if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                    cleaned = String(cleaned.dropFirst(prefix.count))
                    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    foundPrefix = true
                    break
                }
            }
        }

        // Capitalize first letter
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }

        return cleaned.isEmpty ? nil : cleaned
    }

    /// Cleans AI description text by removing unwanted prefixes and ensuring proper capitalization
    private func cleanAIDescription(_ description: String?) -> String? {
        return Self.cleanFoodText(description)
    }
}

// MARK: - USDA FoodData Central Service

/// Service for accessing USDA FoodData Central API for comprehensive nutrition data
class USDAFoodDataService {
    static let shared = USDAFoodDataService()
    
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"
    private let session: URLSession
    
    private init() {
        // Create optimized URLSession configuration for USDA API
        let config = URLSessionConfiguration.default
        let usdaTimeout = ConfigurableAIService.optimalTimeout(for: .usdaFoodData)
        config.timeoutIntervalForRequest = usdaTimeout
        config.timeoutIntervalForResource = usdaTimeout * 2
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        self.session = URLSession(configuration: config)
    }
    
    /// Search for food products using USDA FoodData Central API
    /// - Parameter query: Search query string
    /// - Returns: Array of OpenFoodFactsProduct for compatibility with existing UI
    func searchProducts(query: String, pageSize: Int = 15) async throws -> [OpenFoodFactsProduct] {
        #if DEBUG
        print("🇺🇸 Starting USDA FoodData Central search for: '\(query)'")
        #endif
        
        guard let url = URL(string: "\(baseURL)/foods/search") else {
            throw OpenFoodFactsError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let usdaKey = UserDefaults.standard.usdaAPIKey.isEmpty ? "DEMO_KEY" : UserDefaults.standard.usdaAPIKey
        components.queryItems = [
            URLQueryItem(name: "api_key", value: usdaKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey (FNDDS),Branded"),
            URLQueryItem(name: "sortBy", value: "dataType.keyword"),
            URLQueryItem(name: "sortOrder", value: "asc"),
            URLQueryItem(name: "requireAllWords", value: "false") // Allow partial matches for better results
        ]
        
        guard let finalURL = components.url else {
            throw OpenFoodFactsError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = ConfigurableAIService.optimalTimeout(for: .usdaFoodData)
        
        do {
            // Check for task cancellation before making request
            try Task.checkCancellation()
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                #if DEBUG
                print("🇺🇸 USDA: HTTP error \(httpResponse.statusCode)")
                #endif
                if httpResponse.statusCode == 429 {
                    // Map USDA rate limit to a specific error so callers can gracefully fall back
                    throw OpenFoodFactsError.rateLimitExceeded
                }
                // Prefer higher-level router to fall back; pass through server error
                throw OpenFoodFactsError.serverError(httpResponse.statusCode)
            }
            
            // Parse USDA response with detailed error handling
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("🇺🇸 USDA: Invalid JSON response format")
                #endif
                throw OpenFoodFactsError.decodingError(NSError(domain: "USDA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"]))
            }
            
            // Check for API errors in response
            if let error = jsonResponse["error"] as? [String: Any],
               let code = error["code"] as? String,
               let message = error["message"] as? String {
                #if DEBUG
                print("🇺🇸 USDA: API error - \(code): \(message)")
                #endif
                throw OpenFoodFactsError.serverError(400)
            }
            
            guard let foods = jsonResponse["foods"] as? [[String: Any]] else {
                #if DEBUG
                print("🇺🇸 USDA: No foods array in response")
                #endif
                throw OpenFoodFactsError.noData
            }
            
            #if DEBUG
            print("🇺🇸 USDA: Raw API returned \(foods.count) food items")
            #endif
            
            // Check for task cancellation before processing results
            try Task.checkCancellation()
            
            // Convert USDA foods to OpenFoodFactsProduct format for UI compatibility
            let products = foods.compactMap { foodData -> OpenFoodFactsProduct? in
                // Check for cancellation during processing to allow fast cancellation
                if Task.isCancelled {
                    return nil
                }
                return convertUSDAFoodToProduct(foodData)
            }
            
            #if DEBUG
            print("🇺🇸 USDA search completed: \(products.count) valid products found (filtered from \(foods.count) raw items)")
            #endif
            return products
            
        } catch {
            #if DEBUG
            print("🇺🇸 USDA search failed: \(error)")
            #endif
            
            // Handle task cancellation gracefully
            if error is CancellationError {
                #if DEBUG
                print("🇺🇸 USDA: Task was cancelled (expected behavior during rapid typing)")
                #endif
                return []
            }
            
            if let urlError = error as? URLError, urlError.code == .cancelled {
                #if DEBUG
                print("🇺🇸 USDA: URLSession request was cancelled (expected behavior during rapid typing)")
                #endif
                return []
            }
            
            throw OpenFoodFactsError.networkError(error)
        }
    }
    
    /// Convert USDA food data to OpenFoodFactsProduct for UI compatibility
    private func convertUSDAFoodToProduct(_ foodData: [String: Any]) -> OpenFoodFactsProduct? {
        guard let fdcId = foodData["fdcId"] as? Int,
              let description = foodData["description"] as? String else {
            #if DEBUG
            print("🇺🇸 USDA: Missing fdcId or description for food item")
            #endif
            return nil
        }
        
        // Extract nutrition data from USDA food nutrients with comprehensive mapping
        var carbs: Double = 0
        var protein: Double = 0
        var fat: Double = 0
        var fiber: Double = 0
        var sugars: Double = 0
        var energy: Double = 0
        
        // Track what nutrients we found for debugging
        var foundNutrients: [String] = []
        
        if let foodNutrients = foodData["foodNutrients"] as? [[String: Any]] {
            #if DEBUG
            print("🇺🇸 USDA: Found \(foodNutrients.count) nutrients for '\(description)'")
            #endif
            
            for nutrient in foodNutrients {
                // Debug: print the structure of the first few nutrients
                if foundNutrients.count < 3 {
                    #if DEBUG
                    print("🇺🇸 USDA: Nutrient structure: \(nutrient)")
                    #endif
                }
                
                // Try different possible field names for nutrient number
                var nutrientNumber: Int?
                if let number = nutrient["nutrientNumber"] as? Int {
                    nutrientNumber = number
                } else if let number = nutrient["nutrientId"] as? Int {
                    nutrientNumber = number
                } else if let numberString = nutrient["nutrientNumber"] as? String,
                          let number = Int(numberString) {
                    nutrientNumber = number
                } else if let numberString = nutrient["nutrientId"] as? String,
                          let number = Int(numberString) {
                    nutrientNumber = number
                }
                
                guard let nutrientNum = nutrientNumber else {
                    continue
                }
                
                // Handle both Double and String values from USDA API
                var value: Double = 0
                if let doubleValue = nutrient["value"] as? Double {
                    value = doubleValue
                } else if let stringValue = nutrient["value"] as? String,
                          let parsedValue = Double(stringValue) {
                    value = parsedValue
                } else if let doubleValue = nutrient["amount"] as? Double {
                    value = doubleValue
                } else if let stringValue = nutrient["amount"] as? String,
                          let parsedValue = Double(stringValue) {
                    value = parsedValue
                } else {
                    continue
                }
                
                // Comprehensive USDA nutrient number mapping
                switch nutrientNum {
                // Carbohydrates - multiple possible sources
                case 205: // Carbohydrate, by difference (most common)
                    carbs = value
                    foundNutrients.append("carbs-205")
                case 1005: // Carbohydrate, by summation
                    if carbs == 0 { carbs = value }
                    foundNutrients.append("carbs-1005")
                case 1050: // Carbohydrate, other
                    if carbs == 0 { carbs = value }
                    foundNutrients.append("carbs-1050")
                    
                // Protein - multiple possible sources  
                case 203: // Protein (most common)
                    protein = value
                    foundNutrients.append("protein-203")
                case 1003: // Protein, crude
                    if protein == 0 { protein = value }
                    foundNutrients.append("protein-1003")
                    
                // Fat - multiple possible sources
                case 204: // Total lipid (fat) (most common)
                    fat = value
                    foundNutrients.append("fat-204")
                case 1004: // Total lipid, crude
                    if fat == 0 { fat = value }
                    foundNutrients.append("fat-1004")
                    
                // Fiber - multiple possible sources
                case 291: // Fiber, total dietary (most common)
                    fiber = value
                    foundNutrients.append("fiber-291")
                case 1079: // Fiber, crude
                    if fiber == 0 { fiber = value }
                    foundNutrients.append("fiber-1079")
                    
                // Sugars - multiple possible sources
                case 269: // Sugars, total including NLEA (most common)
                    sugars = value
                    foundNutrients.append("sugars-269")
                case 1010: // Sugars, total
                    if sugars == 0 { sugars = value }
                    foundNutrients.append("sugars-1010")
                case 1063: // Sugars, added
                    if sugars == 0 { sugars = value }
                    foundNutrients.append("sugars-1063")
                    
                // Energy/Calories - multiple possible sources
                case 208: // Energy (kcal) (most common)
                    energy = value
                    foundNutrients.append("energy-208")
                case 1008: // Energy, gross
                    if energy == 0 { energy = value }
                    foundNutrients.append("energy-1008")
                case 1062: // Energy, metabolizable
                    if energy == 0 { energy = value }
                    foundNutrients.append("energy-1062")
                    
                default:
                    break
                }
            }
        } else {
            #if DEBUG
            print("🇺🇸 USDA: No foodNutrients array found in food data for '\(description)'")
            #endif
            #if DEBUG
            print("🇺🇸 USDA: Available keys in foodData: \(Array(foodData.keys))")
            #endif
        }
        
        // Log what we found for debugging
        if foundNutrients.isEmpty {
            #if DEBUG
            print("🇺🇸 USDA: No recognized nutrients found for '\(description)' (fdcId: \(fdcId))")
            #endif
        } else {
            #if DEBUG
            print("🇺🇸 USDA: Found nutrients for '\(description)': \(foundNutrients.joined(separator: ", "))")
            #endif
        }
        
        // Enhanced data quality validation
        let hasUsableNutrientData = carbs > 0 || protein > 0 || fat > 0 || energy > 0
        if !hasUsableNutrientData {
            #if DEBUG
            print("🇺🇸 USDA: Skipping '\(description)' - no usable nutrient data (carbs: \(carbs), protein: \(protein), fat: \(fat), energy: \(energy))")
            #endif
            return nil
        }
        
        // Create nutriments object with comprehensive data
        let nutriments = Nutriments(
            carbohydrates: carbs,
            proteins: protein > 0 ? protein : nil,
            fat: fat > 0 ? fat : nil,
            calories: energy > 0 ? energy : nil,
            sugars: sugars > 0 ? sugars : nil,
            fiber: fiber > 0 ? fiber : nil,
            energy: energy > 0 ? energy : nil
        )
        
        // Create product with USDA data
        return OpenFoodFactsProduct(
            id: String(fdcId),
            productName: cleanUSDADescription(description),
            brands: "USDA FoodData Central",
            categories: categorizeUSDAFood(description),
            nutriments: nutriments,
            servingSize: "100g", // USDA data is typically per 100g
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontURL: nil,
            code: String(fdcId)
        )
    }
    
    /// Clean up USDA food descriptions for better readability
    private func cleanUSDADescription(_ description: String) -> String {
        var cleaned = description
        
        // Remove common USDA technical terms and codes
        let removals = [
            ", raw", ", cooked", ", boiled", ", steamed",
            ", NFS", ", NS as to form", ", not further specified",
            "USDA Commodity", "Food and Nutrition Service",
            ", UPC: ", "\\b\\d{5,}\\b" // Remove long numeric codes
        ]
        
        for removal in removals {
            if removal.starts(with: "\\") {
                // Handle regex patterns
                cleaned = cleaned.replacingOccurrences(
                    of: removal,
                    with: "",
                    options: .regularExpression
                )
            } else {
                cleaned = cleaned.replacingOccurrences(of: removal, with: "")
            }
        }
        
        // Capitalize properly and trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure first letter is capitalized
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        
        return cleaned.isEmpty ? "USDA Food Item" : cleaned
    }
    
    /// Categorize USDA food items based on their description
    private func categorizeUSDAFood(_ description: String) -> String? {
        let lowercased = description.lowercased()
        
        // Define category mappings based on common USDA food terms
        let categories: [String: [String]] = [
            "Fruits": ["apple", "banana", "orange", "berry", "grape", "peach", "pear", "plum", "cherry", "melon", "fruit"],
            "Vegetables": ["broccoli", "carrot", "spinach", "lettuce", "tomato", "onion", "pepper", "cucumber", "vegetable"],
            "Grains": ["bread", "rice", "pasta", "cereal", "oat", "wheat", "barley", "quinoa", "grain"],
            "Dairy": ["milk", "cheese", "yogurt", "butter", "cream", "dairy"],
            "Protein": ["chicken", "beef", "pork", "fish", "egg", "meat", "turkey", "salmon", "tuna"],
            "Nuts & Seeds": ["nut", "seed", "almond", "peanut", "walnut", "cashew", "sunflower"],
            "Beverages": ["juice", "beverage", "drink", "soda", "tea", "coffee"],
            "Snacks": ["chip", "cookie", "cracker", "candy", "chocolate", "snack"]
        ]
        
        for (category, keywords) in categories {
            if keywords.contains(where: { lowercased.contains($0) }) {
                return category
            }
        }
        
        return nil
    }
}

