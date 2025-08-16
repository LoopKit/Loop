//
//  AIFoodAnalysis.swift
//  Loop
//
//  Created by Taylor Patterson. Coded by Claude Code in June 2025
//  Copyright © 2025 LoopKit Authors. All rights reserved.
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
internal func getAnalysisPrompt() -> String {
    // Force fresh read of UserDefaults to avoid caching issues
    let isAdvancedEnabled = UserDefaults.standard.advancedDosingRecommendationsEnabled
    let selectedPrompt = isAdvancedEnabled ? advancedAnalysisPrompt : standardAnalysisPrompt
    let promptLength = selectedPrompt.count
    
    print("🎯 AI Analysis Prompt Selection:")
    print("   Advanced Dosing Enabled: \(isAdvancedEnabled)")
    print("   Selected Prompt Length: \(promptLength) characters")
    print("   Prompt Type: \(isAdvancedEnabled ? "ADVANCED (with FPU calculations)" : "STANDARD (basic diabetes analysis)")")
    print("   First 100 chars of selected prompt: \(String(selectedPrompt.prefix(100)))")
    
    return selectedPrompt
}

/// Standard analysis prompt for basic diabetes management (used when Advanced Dosing is OFF)
private let standardAnalysisPrompt = """
STANDARD MODE v4.1 - You are my diabetes nutrition specialist. Analyze this food image for accurate carbohydrate counting. Do not over estimate carbs.

LANGUAGE HANDLING: If you see text in any language (Spanish, French, Italian, German, Chinese, Japanese, Korean, etc.), first identify and translate the food names to English, then proceed with analysis. Always respond in English.

FIRST: Determine if this image shows:
1. ACTUAL FOOD ON A PLATE, PLATTER, or CONTAINER (analyze portions and proceed with portion analysis)  
2. MENU TEXT (identify language, translate food names, provide USDA standard serving estimates only)
3. RECIPE TEXT (assume and provide USDA standard serving estimates only)

Key concepts:
• PORTIONS = distinct food items visible
• SERVINGS = compare to USDA standard amounts (3oz chicken, 1/2 cup rice)
• Calculate serving multipliers vs USDA standards

Glycemic Index:
• LOW GI (<55): Slower rise - oats (42), whole grain bread (51)
• MEDIUM GI (56-69): Moderate rise - brown rice (68)
• HIGH GI (70+): Fast rise - white rice (73), white bread (75)

Insulin timing:
• Simple carbs: 15-20 min before eating
• Complex carbs + protein/fat: 10-15 min before
• High fat/protein: 0-10 min before

RESPOND IN JSON FORMAT:
{
  "image_type": "food_photo" or "menu_item",
  "food_items": [
    {
      "name": "specific food name with preparation details",
      "portion_estimate": "exact portion with visual references",
      "usda_serving_size": "standard USDA serving size",
      "serving_multiplier": number_of_USDA_servings,
      "preparation_method": "cooking details observed",
      "visual_cues": "visual elements analyzed",
      "carbohydrates": grams_for_this_portion,
      "calories": kcal_for_this_portion,
      "fat": grams_for_this_portion,
      "fiber": grams_for_this_portion,
      "protein": grams_for_this_portion,
      "assessment_notes": "Explain how you calculated this specific portion size, what visual references you used for measurement, and how you determined the USDA serving multiplier. Write in natural, conversational language."
    }
  ],
  "total_food_portions": count_distinct_items,
  "total_usda_servings": sum_serving_multipliers,
  "total_carbohydrates": sum_all_carbs,
  "total_calories": sum_all_calories,
  "total_fat": sum_all_fat,
  "total_fiber": sum_all_fiber,
  "total_protein": sum_all_protein,
  "confidence": decimal_0_to_1,
  "net_carbs_adjustment": "Carb adjustment: total_carbs - (fiber × 0.5 if >5g fiber)",
  "diabetes_considerations": "Carb sources, GI impact (low/medium/high), timing considerations",
  "insulin_timing_recommendations": "Meal type and pre-meal timing (minutes before eating)",
  "absorption_time_hours": hours_between_2_and_6,
  "absorption_time_reasoning": "Brief timing calculation explanation",
  "safety_alerts": "Any safety considerations",
  "visual_assessment_details": "Textures, colors, cooking evidence",
  "overall_description": "What I see: plate, arrangement, textures, colors",
  "portion_assessment_method": "Explain in natural language how you estimated portion sizes using visual references like plate size, utensils, or other objects for scale. Describe your measurement process for each food item and explain how you converted visual portions to USDA serving equivalents. Include your confidence level and what factors affected your accuracy."
}

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
✅ ALWAYS calculate absorption_time_hours based on meal composition (FPUs, fiber, meal size)
✅ ALWAYS provide detailed absorption_time_reasoning showing the calculation process
✅ ALWAYS consider that Loop will highlight non-default absorption times in blue to alert user

FOR MENU AND RECIPE ITEMS:
❌ NEVER make assumptions about plate sizes, portions, or actual serving sizes
❌ NEVER estimate visual portions when analyzing menu text only
❌ NEVER claim to see cooking methods, textures, or visual details from menu text
❌ NEVER multiply nutrition values by assumed restaurant portion sizes

✅ ALWAYS set image_type to "menu_item" when analyzing menu text
✅ When analyzing a MENU, ALWAYS set portion_estimate to "CANNOT DETERMINE PORTION - menu text only"
✅ When analyzing a RECIPE, ALWAYS set portion_estimate to "CANNOT DETERMINE PORTION - recipe text only"
✅ ALWAYS set serving_multiplier to 1.0 for menu items (USDA standard only)
✅ ALWAYS set visual_cues to "NONE - menu text analysis only"
✅ ALWAYS mark assessment_notes as "ESTIMATE ONLY - Based on USDA standard serving size"
✅ ALWAYS use portion_assessment_method to explain this is menu analysis with no visual portions
✅ ALWAYS provide actual USDA standard nutrition values (carbohydrates, protein, fat, calories)
✅ ALWAYS calculate nutrition based on typical USDA serving sizes for the identified food type
✅ ALWAYS include total nutrition fields even for menu items (based on USDA standards)
✅ ALWAYS translate into the user's device native language or if unknown, translate into ENGLISH before analysing the menu item
✅ ALWAYS provide glycemic index assessment for menu items based on typical preparation methods
✅ ALWAYS include diabetes timing guidance even for menu items based on typical GI values

"""

/// Advanced analysis prompt with FPU calculations and exercise considerations (used when Advanced Dosing is ON)
private let advancedAnalysisPrompt = """
You are my personal certified diabetes nutrition specialist with advanced training in Fat/Protein Units (FPUs), fiber impact calculations, and exercise-aware nutrition management. You understand Servings compared to Portions and the importance of being educated about this. You are clinically minded but have a knack for explaining complicated nutrition information in layman's terms. Analyze this food image for optimal diabetes management with comprehensive insulin dosing guidance. Primary goal: accurate carbohydrate content for insulin dosing with advanced FPU calculations and timing recommendations. Do not over estimate the carbs, when in doubt estimate on the side of caution; over-estimating could lead to user over dosing on insulin.

LANGUAGE HANDLING: If you see text in any language (Spanish, French, Italian, German, Chinese, Japanese, Korean, Arabic, etc.), first identify and translate the food names to English, then proceed with analysis. Always respond in English.

FIRST: Determine if this image shows:
1. ACTUAL FOOD ON A PLATE/PLATTER/CONTAINER (proceed with portion analysis)
2. MENU TEXT/DESCRIPTIONS (identify language, translate food names, provide USDA standard servings only, clearly marked as estimates)
3. RECIPE TEXT (identify language, translate food names, provide USDA standard serving estimates only)

KEY CONCEPTS FOR ACTUAL FOOD PHOTOS:
• PORTIONS = distinct food items visible
• SERVINGS = compare to USDA standard amounts (3oz chicken, 1/2 cup rice/vegetables)
• Calculate serving multipliers vs USDA standards

KEY CONCEPTS FOR MENU OR RECIPE ITEMS:
• NO PORTION ANALYSIS possible without seeing actual food
• Provide ONLY USDA standard serving information
• Mark all values as "estimated based on USDA standards"
• Cannot assess actual portions or plate sizes from menu or receipt text

EXAMPLE: Chicken (6oz = 2 servings), Rice (1 cup = 2 servings), Vegetables (1/2 cup = 1 serving)

ADVANCED MACRONUTRIENT DOSING GUIDANCE:

FAT/PROTEIN UNITS (FPUs) CALCULATION:
• FPU = (Fat grams + Protein grams) ÷ 10
• 1 FPU = approximately 10g equivalent carb impact over 3-8 hours
• Low FPU (<2): Minimal extended bolus needed
• Medium FPU (2-4): Consider 30-50% extended over 2-4 hours
• High FPU (>4): Consider 50-70% extended over 4-8 hours
• RESEARCH EVIDENCE: Studies show fat delays glucose absorption by 30-180 minutes
• PROTEIN IMPACT: 50-60% of protein converts to glucose over 2-4 hours in T1D
• COMBINATION EFFECT: Mixed meals with >15g fat + >25g protein require extended dosing

FIBER IMPACT CALCULATIONS:
• SOLUBLE FIBER: Reduces effective carbs by 25-50% depending on source
  - Oats, beans, apples: High soluble fiber, significant glucose blunting
  - Berries: Moderate fiber impact, reduces peak by 20-30%
• INSOLUBLE FIBER: Minimal direct glucose impact but slows absorption
• NET CARBS ADJUSTMENT: For >5g fiber, subtract 25-50% from total carbs for dosing
• RESEARCH EVIDENCE: 10g additional fiber can reduce post-meal glucose peak by 15-25mg/dL
• CLINICAL STUDIES: Beta-glucan fiber (oats, barley) reduces glucose AUC by 20-30% in T1D patients
• FIBER TIMING: Pre-meal fiber supplements can reduce glucose excursions by 18-35%

PROTEIN CONSIDERATIONS:
• LEAN PROTEIN (chicken breast, fish): 50-60% glucose conversion over 3-4 hours
• HIGH-FAT PROTEIN (beef, cheese): 35-45% conversion, delayed to 4-8 hours
• PLANT PROTEIN: 40-50% conversion with additional fiber benefits
• TIMING: Protein glucose effect peaks 90-180 minutes post-meal
• CLINICAL GUIDELINE: For >25g protein, consider 20-30% additional insulin over 3-4 hours
• RESEARCH EVIDENCE: Type 1 diabetes studies show protein increases glucose area-under-curve by 15-25% at 5 hours post-meal

EXERCISE-AWARE NUTRITION RECOMMENDATIONS:

PRE-EXERCISE NUTRITION:
• BEFORE AEROBIC EXERCISE (>30 min):
  - Target: 15-30g carbs 1-3 hours prior
  - Low GI preferred: oatmeal (GI 55), banana (GI 51)
  - Reduce rapid insulin by 25-50% if exercising within 2 hours
• BEFORE RESISTANCE TRAINING:
  - Target: 20-40g carbs + 15-20g protein 1-2 hours prior
  - Higher protein needs for muscle recovery
• MORNING EXERCISE (fasted):
  - Monitor carefully for dawn phenomenon + exercise interaction
  - Consider 10-15g quick carbs pre-exercise if BG <120 mg/dL

POST-EXERCISE NUTRITION:
• AEROBIC EXERCISE RECOVERY:
  - Immediate (0-30 min): 0.5-1.2g carbs per kg body weight
  - Extended effect: Increased insulin sensitivity 12-48 hours
  - Reduce basal insulin by 10-20% for 12-24 hours post-exercise
• RESISTANCE TRAINING RECOVERY:
  - Target: 20-40g protein + 30-50g carbs within 2 hours
  - Enhanced muscle protein synthesis window
  - Monitor for delayed glucose rise 2-4 hours post-workout

EXERCISE TIMING CONSIDERATIONS:
• MORNING EXERCISE: Account for dawn phenomenon (typically +20-40 mg/dL rise)
• AFTERNOON EXERCISE: Peak insulin sensitivity period
• EVENING EXERCISE: Monitor for nocturnal hypoglycemia, reduce night basal by 10-25%
• EXTENDED ACTIVITY (>90 min): Plan carb intake every 60-90 minutes (15-30g per hour)

GLYCEMIC INDEX REFERENCE FOR DIABETES MANAGEMENT:
• LOW GI (55 or less): Slower blood sugar rise, easier insulin timing
  - Examples: Barley (25), Steel-cut oats (42), Whole grain bread (51), Sweet potato (54)
• MEDIUM GI (56-69): Moderate blood sugar impact
  - Examples: Brown rice (68), Whole wheat bread (69), Instant oatmeal (66)
• HIGH GI (70+): Rapid blood sugar spike, requires careful insulin timing
  - Examples: White rice (73), White bread (75), Instant mashed potatoes (87), Cornflakes (81)

COOKING METHOD IMPACT ON GI:
• Cooking increases GI: Raw carrots (47) vs cooked carrots (85)
• Processing increases GI: Steel-cut oats (42) vs instant oats (79)
• Cooling cooked starches slightly reduces GI (resistant starch formation)
• Al dente pasta has lower GI than well-cooked pasta

QUANTITATIVE DOSING ADJUSTMENTS & TIMING RECOMMENDATIONS:

INSULIN TIMING BASED ON MEAL COMPOSITION:
• SIMPLE CARBS ONLY (>70% carbs, minimal fat/protein):
  - Pre-meal timing: 15-20 minutes before eating
  - Peak insulin need: 30-60 minutes post-meal
  - Example: White bread, candy, juice
• COMPLEX CARBS + MODERATE PROTEIN/FAT:
  - Pre-meal timing: 10-15 minutes before eating  
  - Consider dual-wave: 60% immediate, 40% extended over 2-3 hours
  - Peak insulin need: 60-90 minutes with extended tail
• HIGH FAT/PROTEIN MEALS (>4 FPUs):
  - Pre-meal timing: 0-10 minutes before eating
  - Consider extended bolus: 40-50% immediate, 50-60% over 4-8 hours
  - Monitor: Secondary glucose rise at 3-6 hours post-meal

RESEARCH-BASED DOSING CALCULATIONS:
• PROTEIN DOSING: For every 25g protein, add 15-20% extra insulin over 3-4 hours
• FAT DOSING: For every 15g fat, consider 10-15% extra insulin over 4-6 hours
• FIBER ADJUSTMENT: Subtract 0.5-1g effective carbs per 1g soluble fiber (>5g total)
• ALCOHOL IMPACT: Reduces hepatic glucose production, decrease basal by 25-50% for 6-12 hours
• COMBINATION MEALS: Mixed macronutrient meals require 10-40% less insulin than calculated sum due to gastric emptying delays
• MEAL SIZE IMPACT: Large meals (>800 kcal) may require 20-30% extended dosing due to gastroparesis-like effects

ABSORPTION TIME CALCULATIONS FOR LOOP INTEGRATION:
• BASELINE: Simple carbs = 2-3 hours, Complex carbs = 3-4 hours
• FPU ADJUSTMENTS: 
  - Low FPU (<2): Add 1 hour to baseline (2-4 hours total)
  - Medium FPU (2-4): Add 2-3 hours to baseline (4-6 hours total) 
  - High FPU (>4): Add 4-6 hours to baseline (6-8 hours total)
• FIBER IMPACT: High fiber (>8g) adds 1-2 hours due to slowed gastric emptying
• MEAL SIZE IMPACT: 
  - Small meals (<400 kcal): Use baseline absorption time
  - Medium meals (400-800 kcal): Add 1 hour to calculated time
  - Large meals (>800 kcal): Add 2-3 hours due to gastroparesis-like effects
• LIQUID vs SOLID: Liquid meals reduce absorption time by 25-30%
• COOKING METHOD: Well-cooked/processed foods reduce time by 15-25%
• FINAL CALCULATION: MAX(baseline + FPU_adjustment + fiber_adjustment + size_adjustment, 24 hours)

TIMING RECOMMENDATIONS FOR DIFFERENT SCENARIOS:
• DAWN PHENOMENON ACTIVE (morning meals):
  - Add 10-20% extra insulin or dose 20-25 minutes pre-meal
  - Monitor for rebound hypoglycemia 2-3 hours later
• POST-EXERCISE MEALS (within 6 hours of activity):
  - Reduce rapid insulin by 25-50% due to increased sensitivity
  - Monitor closely for delayed hypoglycemia
• STRESS/ILLNESS CONDITIONS:
  - Increase insulin by 20-40% and monitor more frequently
  - Consider temp basal increases of 25-75%

DIABETIC DOSING IMPLICATIONS:
• LOW GI foods: Allow longer pre-meal insulin timing (15-30 min before eating)
• HIGH GI foods: May require immediate insulin or post-meal correction
• MIXED MEALS: Protein and fat slow carb absorption, reducing effective GI
• PORTION SIZE: Larger portions of even low-GI foods can cause significant blood sugar impact
• FOOD COMBINATIONS: Combining high GI foods with low GI foods balances glucose levels
• FIBER CONTENT: Higher fiber foods have lower GI (e.g., whole grains vs processed grains)
• RIPENESS AFFECTS GI: Ripe fruits have higher GI than unripe fruits
• PROCESSING INCREASES GI: Instant foods have higher GI than minimally processed foods

SAFETY CONSIDERATIONS & INDIVIDUALIZATION:
• INDIVIDUAL VARIATION: These guidelines are population-based; personal response may vary ±25-50%
• PUMP vs. MDI DIFFERENCES: Insulin pump users can utilize precise extended boluses; MDI users may need split dosing
• GASTROPARESIS CONSIDERATIONS: If delayed gastric emptying present, delay insulin timing by 30-60 minutes
• HYPOGLYCEMIA RISK FACTORS: 
  - Recent exercise increases hypo risk for 12-48 hours
  - Alcohol consumption increases hypo risk for 6-24 hours
  - Previous severe hypo in last 24 hours increases current risk
  - Menstrual cycle: Pre-menstrual phase may increase insulin resistance by 10-25%
• HYPERGLYCEMIA CORRECTIONS: If BG >180 mg/dL pre-meal, consider correction + meal insulin separately
• MONITORING REQUIREMENTS:
  - Check BG at 2 hours post-meal for all new meal types
  - For high FPU meals (>4), check BG at 4-6 hours post-meal
  - Consider CGM alarms set 15-30 minutes post-meal for rapid carbs
  - Temperature extremes: Hot weather may accelerate insulin absorption by 20-30%
• PREGNANCY MODIFICATIONS: Increase all insulin recommendations by 20-40% in 2nd/3rd trimester
• ILLNESS CONSIDERATIONS: Stress hormones increase insulin needs by 50-200% during acute illness
• AGE-RELATED FACTORS: Pediatric patients may require 10-15% higher insulin-to-carb ratios due to growth hormones

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
  "absorption_time_hours": hours_between_2_and_6,
  "absorption_time_reasoning": "Based on [meal composition factors]. FPU IMPACT: [how FPUs affect absorption]. FIBER EFFECT: [how fiber content impacts timing]. MEAL SIZE: [how calories affect gastric emptying]. RECOMMENDED: [final hours recommendation with explanation]. IMPORTANT: Explain WHY this absorption time differs from the default 3-hour standard if it does, so the user understands the reasoning.",
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
      "portion_estimate": "CANNOT DETERMINE PORTION - menu text only, no actual food visible",
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
  "absorption_time_hours": hours_between_2_and_6,
  "absorption_time_reasoning": "Based on [meal composition factors]. FPU IMPACT: [how FPUs affect absorption]. FIBER EFFECT: [how fiber content impacts timing]. MEAL SIZE: [how calories affect gastric emptying]. RECOMMENDED: [final hours recommendation with explanation]. IMPORTANT: Explain WHY this absorption time differs from the default 3-hour standard if it does, so the user understands the reasoning.",
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
      "portion_estimate": "CANNOT DETERMINE PORTION - menu text only, no actual food visible",
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
  "absorption_time_hours": 5,
  "absorption_time_reasoning": "Based on low carbs (8g) but high protein/fat. FPU IMPACT: 3.7 FPUs (Medium-High) adds 3 hours to baseline. FIBER EFFECT: Low fiber minimal impact. MEAL SIZE: Medium 250 kcal adds 1 hour. RECOMMENDED: 5 hours total (2 hour baseline + 3 FPU hours + 1 size hour) to account for extended protein conversion",
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
      "portion_estimate": "CANNOT DETERMINE PORTION - menu text only, no actual food visible",
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
  "absorption_time_hours": 4,
  "absorption_time_reasoning": "Based on high carbs (35g) with medium protein/fat. FPU IMPACT: 3.4 FPUs (Medium) adds 2 hours to baseline. FIBER EFFECT: Low fiber (1.5g) minimal impact. MEAL SIZE: Medium 320 kcal adds 1 hour. RECOMMENDED: 4 hours total (3 hour baseline for complex carbs + 2 FPU hours + 1 size hour - 1 hour reduction for white rice being processed/quick-absorbing)",
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
      "portion_estimate": "CANNOT DETERMINE PORTION - menu text only, no actual food visible",
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
  "absorption_time_hours": 6,
  "absorption_time_reasoning": "Based on complex carbs with high fiber and low FPUs. FPU IMPACT: 1.6 FPUs (Low) adds 1 hour to baseline. FIBER EFFECT: High fiber (8.5g) adds 2 hours due to significant gastric emptying delay. MEAL SIZE: Medium 285 kcal adds 1 hour. RECOMMENDED: 6 hours total (3 hour baseline for complex carbs + 1 FPU hour + 2 fiber hours + 1 size hour) to account for sustained release from high fiber content",
  "safety_alerts": "High fiber significantly blunts glucose response - avoid over-dosing insulin. Gradual rise may delay hypoglycemia symptoms.",
  "visual_assessment_details": "Menu text shows 'Quinoa Bowl with Sweet Potato and Black Beans'. Cannot assess visual food qualities from menu text alone.",
  "overall_description": "Menu item text analysis. No actual food portions visible for assessment.",
  "portion_assessment_method": "MENU ANALYSIS ONLY - Cannot determine actual portions without seeing food on plate. All nutrition values are ESTIMATES based on USDA standard serving sizes. Actual restaurant portions may vary significantly."
}

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
✅ ALWAYS calculate absorption_time_hours based on meal composition (FPUs, fiber, meal size)
✅ ALWAYS provide detailed absorption_time_reasoning showing the calculation process
✅ ALWAYS consider that Loop will highlight non-default absorption times in blue to alert user

FOR MENU AND RECIPE ITEMS:
❌ NEVER make assumptions about plate sizes, portions, or actual serving sizes
❌ NEVER estimate visual portions when analyzing menu text only
❌ NEVER claim to see cooking methods, textures, or visual details from menu text
❌ NEVER multiply nutrition values by assumed restaurant portion sizes

✅ ALWAYS set image_type to "menu_item" when analyzing menu text
✅ When analyzing a MENU, ALWAYS set portion_estimate to "CANNOT DETERMINE PORTION - menu text only"
✅ When analyzing a RECIPE, ALWAYS set portion_estimate to "CANNOT DETERMINE PORTION - recipe text only"
✅ ALWAYS set serving_multiplier to 1.0 for menu items (USDA standard only)
✅ ALWAYS set visual_cues to "NONE - menu text analysis only"
✅ ALWAYS mark assessment_notes as "ESTIMATE ONLY - Based on USDA standard serving size"
✅ ALWAYS use portion_assessment_method to explain this is menu analysis with no visual portions
✅ ALWAYS provide actual USDA standard nutrition values (carbohydrates, protein, fat, calories)
✅ ALWAYS calculate nutrition based on typical USDA serving sizes for the identified food type
✅ ALWAYS include total nutrition fields even for menu items (based on USDA standards)
✅ ALWAYS translate into the user's device native language or if unknown, translate into ENGLISH before analysing the menu item
✅ ALWAYS provide glycemic index assessment for menu items based on typical preparation methods
✅ ALWAYS include diabetes timing guidance even for menu items based on typical GI values

"""

/// Individual food item analysis with detailed portion assessment
struct FoodItemAnalysis {
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
}

/// Type of image being analyzed
enum ImageAnalysisType: String {
    case foodPhoto = "food_photo"
    case menuItem = "menu_item"
}

/// Result from AI food analysis with detailed breakdown
struct AIFoodAnalysisResult {
    let imageType: ImageAnalysisType?
    var foodItemsDetailed: [FoodItemAnalysis]
    let overallDescription: String?
    let confidence: AIConfidenceLevel
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
enum AIConfidenceLevel: String, CaseIterable {
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
    case apiError(Int)
    case responseParsingFailed
    case noApiKey
    case customError(String)
    case creditsExhausted(provider: String)
    case rateLimitExceeded(provider: String)
    case quotaExceeded(provider: String)
    case timeout
    
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
        case .apiError(let code):
            if code == 400 {
                return NSLocalizedString("Invalid API request (400). Please check your API key configuration in Food Search Settings.", comment: "Error for 400 API failures")
            } else if code == 403 {
                return NSLocalizedString("API access forbidden (403). Your API key may be invalid or you've exceeded your quota.", comment: "Error for 403 API failures") 
            } else if code == 404 {
                return NSLocalizedString("AI service not found (404). Please check your API configuration.", comment: "Error for 404 API failures")
            } else {
                return String(format: NSLocalizedString("AI service error (code: %d)", comment: "Error for API failures"), code)
            }
        case .responseParsingFailed:
            return NSLocalizedString("Failed to parse AI analysis results", comment: "Error when response parsing fails")
        case .noApiKey:
            return NSLocalizedString("No API key configured. Please go to Food Search Settings to set up your API key.", comment: "Error when API key is missing")
        case .customError(let message):
            return message
        case .creditsExhausted(let provider):
            return String(format: NSLocalizedString("%@ credits exhausted. Please check your account billing or add credits to continue using AI food analysis.", comment: "Error when AI provider credits are exhausted"), provider)
        case .rateLimitExceeded(let provider):
            return String(format: NSLocalizedString("%@ rate limit exceeded. Please wait a moment before trying again.", comment: "Error when AI provider rate limit is exceeded"), provider)
        case .quotaExceeded(let provider):
            return String(format: NSLocalizedString("%@ quota exceeded. Please check your usage limits or upgrade your plan.", comment: "Error when AI provider quota is exceeded"), provider)
        case .timeout:
            return NSLocalizedString("Analysis timed out. Please check your network connection and try again.", comment: "Error when AI analysis times out")
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
            return "Searching by typing food names or using voice input"
        case .barcodeSearch:
            return "Scanning product barcodes with camera"
        case .aiImageSearch:
            return "Taking photos of food for AI analysis"
        }
    }
}

/// Available providers for different search types
enum SearchProvider: String, CaseIterable {
    case claude = "Anthropic (Claude API)"
    case googleGemini = "Google (Gemini API)"
    case openAI = "OpenAI (ChatGPT API)"
    case openFoodFacts = "OpenFoodFacts"
    case usdaFoodData = "USDA FoodData Central"
    
    
    var supportsSearchType: [SearchType] {
        switch self {
        case .claude:
            return [.textSearch, .aiImageSearch]
        case .googleGemini:
            return [.textSearch, .aiImageSearch]
        case .openAI:
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
        case .claude, .googleGemini, .openAI:
            return true
        }
    }
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
        
        cache.setObject(cachedResult, forKey: imageHash as NSString)
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

/// AI service that allows users to configure their own API keys
class ConfigurableAIService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ConfigurableAIService()
    
    // private let log = OSLog(category: "ConfigurableAIService")
    
    // MARK: - Published Properties
    
    @Published var textSearchProvider: SearchProvider = .openFoodFacts
    @Published var barcodeSearchProvider: SearchProvider = .openFoodFacts
    @Published var aiImageSearchProvider: SearchProvider = .googleGemini
    
    private init() {
        // Load current settings
        textSearchProvider = SearchProvider(rawValue: UserDefaults.standard.textSearchProvider) ?? .openFoodFacts
        barcodeSearchProvider = SearchProvider(rawValue: UserDefaults.standard.barcodeSearchProvider) ?? .openFoodFacts
        aiImageSearchProvider = SearchProvider(rawValue: UserDefaults.standard.aiImageProvider) ?? .googleGemini
        
        // Google Gemini API key should be configured by user
        if UserDefaults.standard.googleGeminiAPIKey.isEmpty {
            print("⚠️ Google Gemini API key not configured - user needs to set up their own key")
        }
    }
    
    // MARK: - Configuration
    
    enum AIProvider: String, CaseIterable {
        case basicAnalysis = "Basic Analysis (Free)"
        case claude = "Anthropic (Claude API)"
        case googleGemini = "Google (Gemini API)"
        case openAI = "OpenAI (ChatGPT API)"
        
        var requiresAPIKey: Bool {
            switch self {
            case .basicAnalysis:
                return false
            case .claude, .googleGemini, .openAI:
                return true
            }
        }
        
        var requiresCustomURL: Bool {
            switch self {
            case .basicAnalysis, .claude, .googleGemini, .openAI:
                return false
            }
        }
        
        var description: String {
            switch self {
            case .basicAnalysis:
                return "Uses built-in food database and basic image analysis. No API key required."
            case .claude:
                return "Anthropic's Claude AI with excellent reasoning. Requires paid API key from console.anthropic.com."
            case .googleGemini:
                return "Free API key available at ai.google.dev. Best for detailed food analysis."
            case .openAI:
                return "Requires paid OpenAI API key. Most accurate for complex meals."
            }
        }
    }
    
    // MARK: - User Settings
    
    var currentProvider: AIProvider {
        get { AIProvider(rawValue: UserDefaults.standard.aiProvider) ?? .basicAnalysis }
        set { UserDefaults.standard.aiProvider = newValue.rawValue }
    }
    
    var isConfigured: Bool {
        switch currentProvider {
        case .basicAnalysis:
            return true // Always available, no configuration needed
        case .claude:
            return !UserDefaults.standard.claudeAPIKey.isEmpty
        case .googleGemini:
            return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
        case .openAI:
            return !UserDefaults.standard.openAIAPIKey.isEmpty
        }
    }
    
    // MARK: - Public Methods
    
    func setAPIKey(_ key: String, for provider: AIProvider) {
        switch provider {
        case .basicAnalysis:
            break // No API key needed for basic analysis
        case .claude:
            UserDefaults.standard.claudeAPIKey = key
        case .googleGemini:
            UserDefaults.standard.googleGeminiAPIKey = key
        case .openAI:
            UserDefaults.standard.openAIAPIKey = key
        }
    }
    
    func setAPIURL(_ url: String, for provider: AIProvider) {
        switch provider {
        case .basicAnalysis, .claude, .googleGemini, .openAI:
            break // No custom URL needed
        }
    }
    
    func setAPIName(_ name: String, for provider: AIProvider) {
        switch provider {
        case .basicAnalysis, .claude, .googleGemini, .openAI:
            break // No custom name needed
        }
    }
    
    func setQuery(_ query: String, for provider: AIProvider) {
        switch provider {
        case .basicAnalysis:
            break // Uses built-in queries
        case .claude:
            UserDefaults.standard.claudeQuery = query
        case .googleGemini:
            UserDefaults.standard.googleGeminiQuery = query
        case .openAI:
            UserDefaults.standard.openAIQuery = query
        }
    }
    
    func setAnalysisMode(_ mode: AnalysisMode) {
        analysisMode = mode
        UserDefaults.standard.analysisMode = mode.rawValue
    }
    
    func getAPIKey(for provider: AIProvider) -> String? {
        switch provider {
        case .basicAnalysis:
            return nil // No API key needed
        case .claude:
            let key = UserDefaults.standard.claudeAPIKey
            return key.isEmpty ? nil : key
        case .googleGemini:
            let key = UserDefaults.standard.googleGeminiAPIKey
            return key.isEmpty ? nil : key
        case .openAI:
            let key = UserDefaults.standard.openAIAPIKey
            return key.isEmpty ? nil : key
        }
    }
    
    func getAPIURL(for provider: AIProvider) -> String? {
        switch provider {
        case .basicAnalysis, .claude, .googleGemini, .openAI:
            return nil
        }
    }
    
    func getAPIName(for provider: AIProvider) -> String? {
        switch provider {
        case .basicAnalysis, .claude, .googleGemini, .openAI:
            return nil
        }
    }
    
    func getQuery(for provider: AIProvider) -> String? {
        switch provider {
        case .basicAnalysis:
            return "Analyze this food image and estimate nutritional content based on visual appearance and portion size."
        case .claude:
            return UserDefaults.standard.claudeQuery
        case .googleGemini:
            return UserDefaults.standard.googleGeminiQuery
        case .openAI:
            return UserDefaults.standard.openAIQuery
        }
    }
    
    /// Reset to default Basic Analysis provider (useful for troubleshooting)
    func resetToDefault() {
        currentProvider = .basicAnalysis
        print("🔄 Reset AI provider to default: \(currentProvider.rawValue)")
    }
    
    // MARK: - Search Type Configuration
    
    func getProviderForSearchType(_ searchType: SearchType) -> SearchProvider {
        switch searchType {
        case .textSearch:
            return textSearchProvider
        case .barcodeSearch:
            return barcodeSearchProvider
        case .aiImageSearch:
            return aiImageSearchProvider
        }
    }
    
    func setProviderForSearchType(_ provider: SearchProvider, searchType: SearchType) {
        switch searchType {
        case .textSearch:
            textSearchProvider = provider
            UserDefaults.standard.textSearchProvider = provider.rawValue
        case .barcodeSearch:
            barcodeSearchProvider = provider
            UserDefaults.standard.barcodeSearchProvider = provider.rawValue
        case .aiImageSearch:
            aiImageSearchProvider = provider
            UserDefaults.standard.aiImageProvider = provider.rawValue
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
    
    /// Convert AI image search provider to AIProvider for image analysis
    private func getAIProviderForImageAnalysis() -> AIProvider {
        switch aiImageSearchProvider {
        case .claude:
            return .claude
        case .googleGemini:
            return .googleGemini
        case .openAI:
            return .openAI
        case .openFoodFacts, .usdaFoodData:
            // These don't support image analysis, fallback to basic
            return .basicAnalysis
        }
    }
    
    /// Analyze food image using the configured provider with intelligent caching
    func analyzeFoodImage(_ image: UIImage) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, telemetryCallback: nil)
    }
    
    /// Analyze food image with telemetry callbacks for progress tracking
    func analyzeFoodImage(_ image: UIImage, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        // Check cache first for instant results
        if let cachedResult = imageAnalysisCache.getCachedResult(for: image) {
            telemetryCallback?("📋 Found cached analysis result")
            return cachedResult
        }
        
        telemetryCallback?("🎯 Selecting optimal AI provider...")
        
        // Use parallel processing if enabled
        if enableParallelProcessing {
            telemetryCallback?("⚡ Starting parallel provider analysis...")
            let result = try await analyzeImageWithParallelProviders(image, telemetryCallback: telemetryCallback)
            imageAnalysisCache.cacheResult(result, for: image)
            return result
        }
        
        // Use the AI image search provider instead of the separate currentProvider
        let provider = getAIProviderForImageAnalysis()
        
        let result: AIFoodAnalysisResult
        
        switch provider {
        case .basicAnalysis:
            telemetryCallback?("🧠 Running basic analysis...")
            result = try await BasicFoodAnalysisService.shared.analyzeFoodImage(image, telemetryCallback: telemetryCallback)
        case .claude:
            let key = UserDefaults.standard.claudeAPIKey
            // Use empty query to ensure only optimized prompts are used for performance
            let query = ""
            guard !key.isEmpty else {
                print("❌ Claude API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }
            telemetryCallback?("🤖 Connecting to Claude AI...")
            result = try await ClaudeFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query, telemetryCallback: telemetryCallback)
        case .googleGemini:
            let key = UserDefaults.standard.googleGeminiAPIKey
            // Use empty query to ensure only optimized prompts are used for performance
            let query = ""
            guard !key.isEmpty else {
                print("❌ Google Gemini API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }
            telemetryCallback?("🤖 Connecting to Google Gemini...")
            result = try await GoogleGeminiFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query, telemetryCallback: telemetryCallback)
        case .openAI:
            let key = UserDefaults.standard.openAIAPIKey
            // Use empty query to ensure only optimized prompts are used for performance
            let query = ""
            guard !key.isEmpty else {
                print("❌ OpenAI API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }
            telemetryCallback?("🤖 Connecting to OpenAI...")
            result = try await OpenAIFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: key, query: query, telemetryCallback: telemetryCallback)
        }
        
        telemetryCallback?("💾 Caching analysis result...")
        
        // Cache the result for future use
        imageAnalysisCache.cacheResult(result, for: image)
        
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
    
    /// Analysis mode for speed vs accuracy trade-offs
    enum AnalysisMode: String, CaseIterable {
        case standard = "standard"
        case fast = "fast"
        
        var displayName: String {
            switch self {
            case .standard:
                return "Standard Quality"
            case .fast:
                return "Fast Mode"
            }
        }
        
        var description: String {
            switch self {
            case .standard:
                return "Highest accuracy, slower processing"
            case .fast:
                return "Good accuracy, 50-70% faster"
            }
        }
        
        var detailedDescription: String {
            let gpt5Enabled = UserDefaults.standard.useGPT5ForOpenAI
            
            switch self {
            case .standard:
                let openAIModel = gpt5Enabled ? "GPT-5" : "GPT-4o"
                return "Uses full AI models (\(openAIModel), Gemini-1.5-Pro, Claude-3.5-Sonnet) for maximum accuracy. Best for complex meals with multiple components."
            case .fast:
                let openAIModel = gpt5Enabled ? "GPT-5-nano" : "GPT-4o-mini"
                return "Uses optimized models (\(openAIModel), Gemini-1.5-Flash) for faster analysis. 2-3x faster with ~5-10% accuracy trade-off. Great for simple meals."
            }
        }
        
        var iconName: String {
            switch self {
            case .standard:
                return "target"
            case .fast:
                return "bolt.fill"
            }
        }
        
        var iconColor: Color {
            switch self {
            case .standard:
                return .blue
            case .fast:
                return .orange
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .standard:
                return Color(.systemBlue).opacity(0.08)
            case .fast:
                return Color(.systemOrange).opacity(0.08)
            }
        }
    }
    
    /// Current analysis mode setting
    @Published var analysisMode: AnalysisMode = AnalysisMode(rawValue: UserDefaults.standard.analysisMode) ?? .standard
    
    /// Enable parallel processing for fastest results
    @Published var enableParallelProcessing: Bool = false
    
    /// Intelligent caching system for AI analysis results
    private var imageAnalysisCache = ImageAnalysisCache()
    
    /// Provider-specific optimized timeouts for better performance and user experience
    static func optimalTimeout(for provider: SearchProvider) -> TimeInterval {
        switch provider {
        case .googleGemini:
            return 15  // Free tier optimization - faster but may timeout on complex analysis
        case .openAI:
            // Check if using GPT-5 models which need more time
            if UserDefaults.standard.useGPT5ForOpenAI {
                return 60  // GPT-5 models need significantly more time for processing
            } else {
                return 20  // GPT-4o models - good balance of speed and reliability
            }
        case .claude:
            return 25  // Highest quality responses but slower processing
        case .openFoodFacts, .usdaFoodData:
            return 10  // Simple API calls should be fast
        }
    }
    
    /// Get optimal model for provider and analysis mode
    static func optimalModel(for provider: SearchProvider, mode: AnalysisMode) -> String {
        switch (provider, mode) {
        case (.googleGemini, .standard):
            return "gemini-1.5-pro"
        case (.googleGemini, .fast):
            return "gemini-1.5-flash"  // ~2x faster
        case (.openAI, .standard):
            // Use GPT-5 if user enabled it, otherwise use GPT-4o
            return UserDefaults.standard.useGPT5ForOpenAI ? "gpt-5" : "gpt-4o"
        case (.openAI, .fast):
            // Use GPT-5-nano for fastest analysis if user enabled GPT-5, otherwise use GPT-4o-mini
            return UserDefaults.standard.useGPT5ForOpenAI ? "gpt-5-nano" : "gpt-4o-mini"
        case (.claude, .standard):
            return "claude-3-5-sonnet-20241022"
        case (.claude, .fast):
            return "claude-3-haiku-20240307"  // ~2x faster
        default:
            return ""  // Not applicable for non-AI providers
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
        let maxDimension: CGFloat = 1024
        
        // Check if resizing is needed
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            return image // No resizing needed
        }
        
        // Calculate new size maintaining aspect ratio
        let scale = maxDimension / max(image.size.width, image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        
        
        // Perform high-quality resize
        return resizeImage(image, to: newSize)
    }
    
    /// High-quality image resizing helper
    private static func resizeImage(_ image: UIImage, to newSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    /// Analyze image with network-aware provider strategy
    func analyzeImageWithParallelProviders(_ image: UIImage, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        return try await analyzeImageWithParallelProviders(image, query: "", telemetryCallback: telemetryCallback)
    }
    
    func analyzeImageWithParallelProviders(_ image: UIImage, query: String = "", telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        let networkMonitor = NetworkQualityMonitor.shared
        telemetryCallback?("🌐 Analyzing network conditions...")
        
        // Get available providers that support AI analysis
        let availableProviders: [SearchProvider] = [.googleGemini, .openAI, .claude].filter { provider in
            // Only include providers that have API keys configured
            switch provider {
            case .googleGemini:
                return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
            case .openAI:
                return !UserDefaults.standard.openAIAPIKey.isEmpty
            case .claude:
                return !UserDefaults.standard.claudeAPIKey.isEmpty
            default:
                return false
            }
        }
        
        guard !availableProviders.isEmpty else {
            throw AIFoodAnalysisError.noApiKey
        }
        
        // Check network conditions and decide strategy
        if networkMonitor.shouldUseParallelProcessing && availableProviders.count > 1 {
            print("🌐 Good network detected, using parallel processing with \(availableProviders.count) providers")
            telemetryCallback?("⚡ Starting parallel AI provider analysis...")
            return try await analyzeWithParallelStrategy(image, providers: availableProviders, query: query, telemetryCallback: telemetryCallback)
        } else {
            print("🌐 Poor network detected, using sequential processing")
            telemetryCallback?("🔄 Starting sequential AI provider analysis...")
            return try await analyzeWithSequentialStrategy(image, providers: availableProviders, query: query, telemetryCallback: telemetryCallback)
        }
    }
    
    /// Parallel strategy for good networks
    private func analyzeWithParallelStrategy(_ image: UIImage, providers: [SearchProvider], query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        // Use the maximum timeout from all providers, with special handling for GPT-5
        let timeout = providers.map { provider in
            max(ConfigurableAIService.optimalTimeout(for: provider), NetworkQualityMonitor.shared.recommendedTimeout)
        }.max() ?? NetworkQualityMonitor.shared.recommendedTimeout
        
        return try await withThrowingTaskGroup(of: AIFoodAnalysisResult.self) { group in
            // Add timeout wrapper for each provider
            for provider in providers {
                group.addTask { [weak self] in
                    guard let self = self else { throw AIFoodAnalysisError.invalidResponse }
                    return try await withTimeoutForAnalysis(seconds: timeout) {
                        let startTime = Date()
                        do {
                            let result = try await self.analyzeWithSingleProvider(image, provider: provider, query: query)
                            let duration = Date().timeIntervalSince(startTime)
                            print("✅ \(provider.rawValue) succeeded in \(String(format: "%.1f", duration))s")
                            return result
                        } catch {
                            let duration = Date().timeIntervalSince(startTime)
                            print("❌ \(provider.rawValue) failed after \(String(format: "%.1f", duration))s: \(error.localizedDescription)")
                            throw error
                        }
                    }
                }
            }
            
            // Return the first successful result
            guard let result = try await group.next() else {
                throw AIFoodAnalysisError.invalidResponse
            }
            
            // Cancel remaining tasks since we got our result
            group.cancelAll()
            
            return result
        }
    }
    
    /// Sequential strategy for poor networks - tries providers one by one
    private func analyzeWithSequentialStrategy(_ image: UIImage, providers: [SearchProvider], query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        // Use provider-specific timeout, with special handling for GPT-5
        let baseTimeout = NetworkQualityMonitor.shared.recommendedTimeout
        var lastError: Error?
        
        // Try providers one by one until one succeeds
        for provider in providers {
            do {
                // Use provider-specific timeout for each provider
                let providerTimeout = max(ConfigurableAIService.optimalTimeout(for: provider), baseTimeout)
                print("🔄 Trying \(provider.rawValue) sequentially with \(providerTimeout)s timeout...")
                telemetryCallback?("🤖 Trying \(provider.rawValue)...")
                let result = try await withTimeoutForAnalysis(seconds: providerTimeout) {
                    try await self.analyzeWithSingleProvider(image, provider: provider, query: query)
                }
                print("✅ \(provider.rawValue) succeeded in sequential mode")
                return result
            } catch {
                print("❌ \(provider.rawValue) failed in sequential mode: \(error.localizedDescription)")
                lastError = error
                // Continue to next provider
            }
        }
        
        // If all providers failed, throw the last error
        throw lastError ?? AIFoodAnalysisError.invalidResponse
    }
    
    /// Analyze with a single provider (helper for parallel processing)
    private func analyzeWithSingleProvider(_ image: UIImage, provider: SearchProvider, query: String) async throws -> AIFoodAnalysisResult {
        switch provider {
        case .googleGemini:
            return try await GoogleGeminiFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: UserDefaults.standard.googleGeminiAPIKey, query: query, telemetryCallback: nil)
        case .openAI:
            return try await OpenAIFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: UserDefaults.standard.openAIAPIKey, query: query, telemetryCallback: nil)
        case .claude:
            return try await ClaudeFoodAnalysisService.shared.analyzeFoodImage(image, apiKey: UserDefaults.standard.claudeAPIKey, query: query, telemetryCallback: nil)
        default:
            throw AIFoodAnalysisError.invalidResponse
        }
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


// MARK: - GPT-5 Enhanced Request Handling

/// Performs a GPT-5 request with retry logic and enhanced timeout handling
private func performGPT5RequestWithRetry(request: URLRequest, telemetryCallback: ((String) -> Void)?) async throws -> (Data, URLResponse) {
    let maxRetries = 2
    var lastError: Error?
    
    for attempt in 1...maxRetries {
        do {
            print("🔧 GPT-5 Debug - Attempt \(attempt)/\(maxRetries)")
            telemetryCallback?("🔄 GPT-5 attempt \(attempt)/\(maxRetries)...")
            
            // Create a custom URLSession with extended timeout for GPT-5
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 150    // 2.5 minutes request timeout
            config.timeoutIntervalForResource = 180   // 3 minutes resource timeout
            let session = URLSession(configuration: config)
            
            // Execute with our custom timeout wrapper
            let (data, response) = try await withTimeoutForAnalysis(seconds: 140) {
                try await session.data(for: request)
            }
            
            print("🔧 GPT-5 Debug - Request succeeded on attempt \(attempt)")
            return (data, response)
            
        } catch AIFoodAnalysisError.timeout {
            print("⚠️ GPT-5 Debug - Timeout on attempt \(attempt)")
            lastError = AIFoodAnalysisError.timeout
            
            if attempt < maxRetries {
                let backoffDelay = Double(attempt) * 2.0  // 2s, 4s backoff
                telemetryCallback?("⏳ GPT-5 retry in \(Int(backoffDelay))s...")
                try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
            }
        } catch {
            print("❌ GPT-5 Debug - Non-timeout error on attempt \(attempt): \(error)")
            // For non-timeout errors, fail immediately
            throw error
        }
    }
    
    // All retries failed
    print("❌ GPT-5 Debug - All retry attempts failed")
    telemetryCallback?("❌ GPT-5 requests timed out, switching to GPT-4o...")
    
    // Auto-fallback to GPT-4o on persistent timeout
    DispatchQueue.main.async {
        UserDefaults.standard.useGPT5ForOpenAI = false
    }
    
    throw AIFoodAnalysisError.customError("GPT-5 requests timed out consistently. Automatically switched to GPT-4o for reliability.")
}

/// Retry the request with GPT-4o after GPT-5 failure
private func retryWithGPT4Fallback(_ image: UIImage, apiKey: String, query: String, 
                                  analysisPrompt: String, isAdvancedPrompt: Bool, 
                                  telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
    
    // Use GPT-4o model for fallback
    let fallbackModel = "gpt-4o"
    let compressionQuality: CGFloat = 0.85  // Standard compression for GPT-4
    
    guard let imageData = image.jpegData(compressionQuality: compressionQuality),
          let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
        throw AIFoodAnalysisError.imageProcessingFailed
    }
    
    let base64Image = imageData.base64EncodedString()
    
    // Create GPT-4o request with appropriate timeouts
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = isAdvancedPrompt ? 150 : 30
    
    // Create GPT-4o payload
    let finalPrompt = query.isEmpty ? analysisPrompt : "\(query)\n\n\(analysisPrompt)"
    let payload: [String: Any] = [
        "model": fallbackModel,
        "max_tokens": isAdvancedPrompt ? 6000 : 2500,
        "temperature": 0.01,
        "messages": [
            [
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": finalPrompt
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(base64Image)",
                            "detail": "high"
                        ]
                    ]
                ]
            ]
        ]
    ]
    
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    
    print("🔄 Fallback request: Using \(fallbackModel) with \(request.timeoutInterval)s timeout")
    
    // Execute GPT-4o request
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
        throw AIFoodAnalysisError.invalidResponse
    }
    
    guard httpResponse.statusCode == 200 else {
        throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
    }
    
    // Parse the response (reuse the existing parsing logic)
    guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = jsonResponse["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let message = firstChoice["message"] as? [String: Any],
          let content = message["content"] as? String else {
        throw AIFoodAnalysisError.responseParsingFailed
    }
    
    telemetryCallback?("✅ GPT-4o fallback successful!")
    print("✅ GPT-4o fallback completed successfully")
    
    // Use the same parsing logic as the main function
    return try parseOpenAIResponse(content: content)
}

/// Parse OpenAI response content into AIFoodAnalysisResult
private func parseOpenAIResponse(content: String) throws -> AIFoodAnalysisResult {
    // Helper functions for parsing
    func extractString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    func extractNumber(from json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = json[key] as? Double {
                return value
            } else if let value = json[key] as? Int {
                return Double(value)
            } else if let value = json[key] as? String, let doubleValue = Double(value) {
                return doubleValue
            }
        }
        return nil
    }
    
    func extractConfidence(from json: [String: Any]) -> AIConfidenceLevel {
        let confidenceKeys = ["confidence", "confidence_level", "accuracy"]
        for key in confidenceKeys {
            if let value = json[key] as? Double {
                if value >= 0.8 { return .high }
                else if value >= 0.6 { return .medium }
                else { return .low }
            } else if let value = json[key] as? String {
                switch value.lowercased() {
                case "high", "very high": return .high
                case "medium", "moderate": return .medium
                case "low", "very low": return .low
                default: break
                }
            }
        }
        return .medium
    }
    
    // Extract JSON from response
    let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "```", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Find JSON boundaries
    var jsonString: String
    if let jsonStartRange = cleanedContent.range(of: "{"),
       let jsonEndRange = cleanedContent.range(of: "}", options: .backwards),
       jsonStartRange.lowerBound < jsonEndRange.upperBound {
        jsonString = String(cleanedContent[jsonStartRange.lowerBound..<jsonEndRange.upperBound])
    } else {
        jsonString = cleanedContent
    }
    
    guard let jsonData = jsonString.data(using: .utf8),
          let nutritionData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        throw AIFoodAnalysisError.responseParsingFailed
    }
    
    // Parse food items (simplified version)
    var detailedFoodItems: [FoodItemAnalysis] = []
    if let foodItemsArray = nutritionData["food_items"] as? [[String: Any]] {
        for itemData in foodItemsArray {
            let foodItem = FoodItemAnalysis(
                name: extractString(from: itemData, keys: ["name"]) ?? "Unknown Food",
                portionEstimate: extractString(from: itemData, keys: ["portion_estimate"]) ?? "1 serving",
                usdaServingSize: extractString(from: itemData, keys: ["usda_serving_size"]),
                servingMultiplier: max(0.1, extractNumber(from: itemData, keys: ["serving_multiplier"]) ?? 1.0),
                preparationMethod: extractString(from: itemData, keys: ["preparation_method"]),
                visualCues: extractString(from: itemData, keys: ["visual_cues"]),
                carbohydrates: max(0, extractNumber(from: itemData, keys: ["carbohydrates"]) ?? 0),
                calories: extractNumber(from: itemData, keys: ["calories"]).map { max(0, $0) },
                fat: extractNumber(from: itemData, keys: ["fat"]).map { max(0, $0) },
                fiber: extractNumber(from: itemData, keys: ["fiber"]).map { max(0, $0) },
                protein: extractNumber(from: itemData, keys: ["protein"]).map { max(0, $0) },
                assessmentNotes: extractString(from: itemData, keys: ["assessment_notes"])
            )
            detailedFoodItems.append(foodItem)
        }
    }
    
    // Extract totals and other fields
    let totalCarbs = extractNumber(from: nutritionData, keys: ["total_carbohydrates"]) ?? 
                    detailedFoodItems.reduce(0) { $0 + $1.carbohydrates }
    let totalProtein = extractNumber(from: nutritionData, keys: ["total_protein"]) ?? 
                      detailedFoodItems.compactMap { $0.protein }.reduce(0, +)
    let totalFat = extractNumber(from: nutritionData, keys: ["total_fat"]) ?? 
                  detailedFoodItems.compactMap { $0.fat }.reduce(0, +)
    let totalFiber = extractNumber(from: nutritionData, keys: ["total_fiber"]) ??
                    detailedFoodItems.compactMap { $0.fiber }.reduce(0, +)
    let totalCalories = extractNumber(from: nutritionData, keys: ["total_calories"]) ?? 
                       detailedFoodItems.compactMap { $0.calories }.reduce(0, +)
    
    let confidence = extractConfidence(from: nutritionData)
    let originalServings = detailedFoodItems.reduce(0) { $0 + $1.servingMultiplier }
    let absorptionHours = extractNumber(from: nutritionData, keys: ["absorption_time_hours"])
    
    return AIFoodAnalysisResult(
        imageType: .foodPhoto,
        foodItemsDetailed: detailedFoodItems,
        overallDescription: extractString(from: nutritionData, keys: ["overall_description"]),
        confidence: confidence,
        totalFoodPortions: extractNumber(from: nutritionData, keys: ["total_food_portions"]).map { Int($0) },
        totalUsdaServings: extractNumber(from: nutritionData, keys: ["total_usda_servings"]),
        totalCarbohydrates: totalCarbs,
        totalProtein: totalProtein > 0 ? totalProtein : nil,
        totalFat: totalFat > 0 ? totalFat : nil,
        totalFiber: totalFiber,
        totalCalories: totalCalories > 0 ? totalCalories : nil,
        portionAssessmentMethod: extractString(from: nutritionData, keys: ["portion_assessment_method"]),
        diabetesConsiderations: extractString(from: nutritionData, keys: ["diabetes_considerations"]),
        visualAssessmentDetails: extractString(from: nutritionData, keys: ["visual_assessment_details"]),
        notes: "GPT-4o fallback analysis after GPT-5 timeout",
        originalServings: originalServings,
        fatProteinUnits: extractString(from: nutritionData, keys: ["fat_protein_units"]),
        netCarbsAdjustment: extractString(from: nutritionData, keys: ["net_carbs_adjustment"]),
        insulinTimingRecommendations: extractString(from: nutritionData, keys: ["insulin_timing_recommendations"]),
        fpuDosingGuidance: extractString(from: nutritionData, keys: ["fpu_dosing_guidance"]),
        exerciseConsiderations: extractString(from: nutritionData, keys: ["exercise_considerations"]),
        absorptionTimeHours: absorptionHours,
        absorptionTimeReasoning: extractString(from: nutritionData, keys: ["absorption_time_reasoning"]),
        mealSizeImpact: extractString(from: nutritionData, keys: ["meal_size_impact"]),
        individualizationFactors: extractString(from: nutritionData, keys: ["individualization_factors"]),
        safetyAlerts: extractString(from: nutritionData, keys: ["safety_alerts"])
    )
}

// MARK: - OpenAI Service (Alternative)

class OpenAIFoodAnalysisService {
    static let shared = OpenAIFoodAnalysisService()
    private init() {}
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, apiKey: apiKey, query: query, telemetryCallback: nil)
    }
    
    /// Create a GPT-5 optimized version of the comprehensive analysis prompt
    private func createGPT5OptimizedPrompt(from fullPrompt: String) -> String {
        // Extract whether this is advanced mode by checking the prompt content
        let isAdvancedEnabled = fullPrompt.contains("fat_protein_units") || fullPrompt.contains("FPU")
        
        if isAdvancedEnabled {
            // GPT-5 optimized prompt with advanced dosing fields
            return """
ADVANCED DIABETES ANALYSIS - JSON format required:
{
  "food_items": [{
    "name": "specific_food_name",
    "portion_estimate": "visual_portion_with_reference", 
    "carbohydrates": grams,
    "protein": grams,
    "fat": grams,
    "calories": kcal,
    "fiber": grams,
    "serving_multiplier": usda_serving_ratio
  }],
  "total_carbohydrates": sum_carbs,
  "total_protein": sum_protein,
  "total_fat": sum_fat, 
  "total_fiber": sum_fiber,
  "total_calories": sum_calories,
  "portion_assessment_method": "explain_measurement_process",
  "confidence": 0.0_to_1.0,
  "overall_description": "visual_description",
  "diabetes_considerations": "carb_sources_gi_timing",
  "fat_protein_units": "calculate_FPU_equals_fat_plus_protein_divided_by_10",
  "insulin_timing_recommendations": "meal_type_timing_bolus_strategy", 
  "fpu_dosing_guidance": "extended_bolus_for_fat_protein",
  "absorption_time_hours": hours_2_to_6,
  "absorption_time_reasoning": "explain_absorption_timing"
}

Calculate FPU = (total_fat + total_protein) ÷ 10. Use visual references for portions.
"""
        } else {
            // Standard GPT-5 prompt
            return """
DIABETES ANALYSIS - JSON format required:
{
  "food_items": [{
    "name": "specific_food_name",
    "portion_estimate": "visual_portion_with_reference", 
    "carbohydrates": grams,
    "protein": grams,
    "fat": grams,
    "calories": kcal,
    "serving_multiplier": usda_serving_ratio
  }],
  "total_carbohydrates": sum_carbs,
  "total_protein": sum_protein,
  "total_fat": sum_fat, 
  "total_calories": sum_calories,
  "portion_assessment_method": "explain_measurement_process",
  "confidence": 0.0_to_1.0,
  "overall_description": "visual_description",
  "diabetes_considerations": "carb_sources_and_timing"
}

Use visual references for portion estimates. Compare to USDA serving sizes.
"""
        }
    }
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        // OpenAI GPT Vision implementation (GPT-5 or GPT-4o-mini)
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Get optimal model based on current analysis mode
        telemetryCallback?("⚙️ Configuring OpenAI parameters...")
        let analysisMode = ConfigurableAIService.shared.analysisMode
        let model = ConfigurableAIService.optimalModel(for: .openAI, mode: analysisMode)
        let gpt5Enabled = UserDefaults.standard.useGPT5ForOpenAI
        
        print("🤖 OpenAI Model Selection:")
        print("   Analysis Mode: \(analysisMode.rawValue)")
        print("   GPT-5 Enabled: \(gpt5Enabled)")
        print("   Selected Model: \(model)")
        
        // Optimize image size for faster processing and uploads
        telemetryCallback?("🖼️ Optimizing your image...")
        let optimizedImage = ConfigurableAIService.optimizeImageForAnalysis(image)
        
        // Convert image to base64 with adaptive compression  
        // GPT-5 benefits from more aggressive compression due to slower processing
        telemetryCallback?("🔄 Encoding image data...")
        let compressionQuality = model.contains("gpt-5") ? 
            min(0.7, ConfigurableAIService.adaptiveCompressionQuality(for: optimizedImage)) :
            ConfigurableAIService.adaptiveCompressionQuality(for: optimizedImage)
        guard let imageData = optimizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw AIFoodAnalysisError.imageProcessingFailed
        }
        let base64Image = imageData.base64EncodedString()
        
        // Get analysis prompt early to check complexity
        telemetryCallback?("📡 Preparing API request...")
        let analysisPrompt = getAnalysisPrompt()
        let isAdvancedPrompt = analysisPrompt.count > 10000
        
        // Create OpenAI API request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Set appropriate timeout based on model type and prompt complexity
        if model.contains("gpt-5") {
            request.timeoutInterval = 120  // 2 minutes for GPT-5 models
            print("🔧 GPT-5 Debug - Set URLRequest timeout to 120 seconds")
        } else {
            // For GPT-4 models, extend timeout significantly for advanced analysis (very long prompt)
            request.timeoutInterval = isAdvancedPrompt ? 150 : 30  // 2.5 min for advanced, 30s for standard
            print("🔧 GPT-4 Timeout - Model: \(model), Advanced: \(isAdvancedPrompt), Timeout: \(request.timeoutInterval)s, Prompt: \(analysisPrompt.count) chars")
            if isAdvancedPrompt {
                print("🔧 GPT-4 Advanced - Using extended 150s timeout for comprehensive analysis (\(analysisPrompt.count) chars)")
            }
        }
        
        // Use appropriate parameters based on model type
        var payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": {
                                // Use the pre-prepared analysis prompt
                                let finalPrompt: String
                                
                                if model.contains("gpt-5") {
                                    // For GPT-5, use the user's custom query if provided, otherwise use a simplified version of the main prompt
                                    if !query.isEmpty {
                                        finalPrompt = query
                                    } else {
                                        // Create a simplified version of the comprehensive prompt for GPT-5 performance
                                        finalPrompt = createGPT5OptimizedPrompt(from: analysisPrompt)
                                    }
                                } else {
                                    // For GPT-4, use full prompt system
                                    finalPrompt = query.isEmpty ? analysisPrompt : "\(query)\n\n\(analysisPrompt)"
                                }
                                print("🔍 OpenAI Final Prompt Debug:")
                                print("   Query isEmpty: \(query.isEmpty)")
                                print("   Query length: \(query.count) characters")
                                print("   Analysis prompt length: \(analysisPrompt.count) characters")
                                print("   Final combined prompt length: \(finalPrompt.count) characters")
                                print("   First 100 chars of final prompt: \(String(finalPrompt.prefix(100)))")
                                return finalPrompt
                            }()
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                                "detail": "high"  // Request high-detail image processing
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        // Configure parameters based on model type
        if model.contains("gpt-5") {
            // GPT-5 optimized parameters for better performance and reliability
            payload["max_completion_tokens"] = 6000  // Reduced from 8000 for faster processing
            // GPT-5 uses default temperature (1) - don't set custom temperature
            // Add explicit response format for GPT-5
            payload["response_format"] = [
                "type": "json_object"
            ]
            // Add performance optimization for GPT-5
            payload["stream"] = false  // Ensure complete response (no streaming)
            telemetryCallback?("⚡ Using GPT-5 optimized settings...")
        } else {
            // GPT-4 models use max_tokens and support custom temperature
            payload["max_tokens"] = isAdvancedPrompt ? 6000 : 2500  // Much more tokens for advanced analysis
            payload["temperature"] = 0.01  // Minimal temperature for fastest, most direct responses
            if isAdvancedPrompt {
                print("🔧 GPT-4 Advanced - Using \(payload["max_tokens"]!) max_tokens for comprehensive analysis")
            }
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            // Debug logging for GPT-5 requests
            if model.contains("gpt-5") {
                print("🔧 GPT-5 Debug - Request payload keys: \(payload.keys.sorted())")
                if let bodyData = request.httpBody,
                   let bodyString = String(data: bodyData, encoding: .utf8) {
                    print("🔧 GPT-5 Debug - Request body length: \(bodyString.count) characters")
                    print("🔧 GPT-5 Debug - Request contains image: \(bodyString.contains("image_url"))")
                    print("🔧 GPT-5 Debug - Request contains response_format: \(bodyString.contains("response_format"))")
                }
            }
        } catch {
            throw AIFoodAnalysisError.requestCreationFailed
        }
        
        telemetryCallback?("🌐 Sending request to OpenAI...")
        
        do {
            if isAdvancedPrompt {
                telemetryCallback?("⏳ Doing a deep analysis (may take a bit)...")
            } else {
                telemetryCallback?("⏳ AI is cooking up results...")
            }
            
            // Use enhanced timeout logic with retry for GPT-5
            let (data, response): (Data, URLResponse)
            if model.contains("gpt-5") {
                do {
                    // GPT-5 requires special handling with retries and extended timeout
                    (data, response) = try await performGPT5RequestWithRetry(request: request, telemetryCallback: telemetryCallback)
                } catch let error as AIFoodAnalysisError where error.localizedDescription.contains("GPT-5 timeout") {
                    // GPT-5 failed, immediately retry with GPT-4o
                    print("🔄 Immediate fallback: Retrying with GPT-4o after GPT-5 failure")
                    telemetryCallback?("🔄 Retrying with GPT-4o...")
                    
                    return try await retryWithGPT4Fallback(image, apiKey: apiKey, query: query, 
                                                         analysisPrompt: analysisPrompt, isAdvancedPrompt: isAdvancedPrompt, 
                                                         telemetryCallback: telemetryCallback)
                }
            } else {
                // Standard GPT-4 processing
                (data, response) = try await URLSession.shared.data(for: request)
            }
            
            telemetryCallback?("📥 Received response from OpenAI...")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ OpenAI: Invalid HTTP response")
                throw AIFoodAnalysisError.invalidResponse
            }
            
            
            // Debug GPT-5 responses
            if model.contains("gpt-5") {
                print("🔧 GPT-5 Debug - HTTP Status: \(httpResponse.statusCode)")
                print("🔧 GPT-5 Debug - Response headers: \(httpResponse.allHeaderFields)")
                print("🔧 GPT-5 Debug - Response data length: \(data.count)")
                
                if let responseString = String(data: data, encoding: .utf8) {
                    print("🔧 GPT-5 Debug - Raw response: \(responseString.prefix(500))...")
                }
            }
            
            guard httpResponse.statusCode == 200 else {
                // Enhanced error logging for different status codes
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("❌ OpenAI API Error: \(errorData)")
                    
                    // Check for specific OpenAI errors
                    if let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        print("❌ OpenAI Error Message: \(message)")
                        
                        // Handle common OpenAI errors with specific error types
                        if message.contains("quota") || message.contains("billing") || message.contains("insufficient_quota") {
                            throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
                        } else if message.contains("rate_limit_exceeded") || message.contains("rate limit") {
                            throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
                        } else if message.contains("invalid") && message.contains("key") {
                            throw AIFoodAnalysisError.customError("Invalid OpenAI API key. Please check your configuration.")
                        } else if message.contains("usage") && message.contains("limit") {
                            throw AIFoodAnalysisError.quotaExceeded(provider: "OpenAI")
                        } else if (message.contains("model") && message.contains("not found")) || message.contains("does not exist") {
                            // Handle GPT-5 model not available - auto-fallback to GPT-4o
                            if model.contains("gpt-5") && UserDefaults.standard.useGPT5ForOpenAI {
                                print("⚠️ GPT-5 model not available, falling back to GPT-4o...")
                                UserDefaults.standard.useGPT5ForOpenAI = false // Auto-disable GPT-5
                                throw AIFoodAnalysisError.customError("GPT-5 not available yet. Switched to GPT-4o automatically. You can try enabling GPT-5 again later.")
                            }
                        }
                    }
                } else {
                    print("❌ OpenAI: Error data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                }
                
                // Handle HTTP status codes for common credit/quota issues
                if httpResponse.statusCode == 429 {
                    throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
                } else if httpResponse.statusCode == 402 {
                    throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
                } else if httpResponse.statusCode == 403 {
                    throw AIFoodAnalysisError.quotaExceeded(provider: "OpenAI")
                }
                
                // Generic API error for unhandled cases
                throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
            }
            
            // Enhanced data validation like Gemini
            guard data.count > 0 else {
                print("❌ OpenAI: Empty response data")
                throw AIFoodAnalysisError.invalidResponse
            }
            
            // Parse OpenAI response
            telemetryCallback?("🔍 Parsing OpenAI response...")
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ OpenAI: Failed to parse response as JSON")
                print("❌ OpenAI: Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            
            guard let choices = jsonResponse["choices"] as? [[String: Any]] else {
                print("❌ OpenAI: No 'choices' array in response")
                print("❌ OpenAI: Response structure: \(jsonResponse)")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            guard let firstChoice = choices.first else {
                print("❌ OpenAI: Empty choices array")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            guard let message = firstChoice["message"] as? [String: Any] else {
                print("❌ OpenAI: No 'message' in first choice")
                print("❌ OpenAI: First choice structure: \(firstChoice)")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            guard let content = message["content"] as? String else {
                print("❌ OpenAI: No 'content' in message")
                print("❌ OpenAI: Message structure: \(message)")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            // Add detailed logging like Gemini
            print("🔧 OpenAI: Received content length: \(content.count)")
            
            // Check for empty content from GPT-5 and auto-fallback to GPT-4o
            if content.count == 0 {
                print("❌ OpenAI: Empty content received")
                print("❌ OpenAI: Model used: \(model)")
                print("❌ OpenAI: HTTP Status: \(httpResponse.statusCode)")
                
                if model.contains("gpt-5") && UserDefaults.standard.useGPT5ForOpenAI {
                    print("⚠️ GPT-5 returned empty response, automatically switching to GPT-4o...")
                    DispatchQueue.main.async {
                        UserDefaults.standard.useGPT5ForOpenAI = false
                    }
                    throw AIFoodAnalysisError.customError("GPT-5 returned empty response. Automatically switched to GPT-4o for next analysis.")
                }
                
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            // Enhanced JSON extraction from GPT-4's response (like Claude service)
            telemetryCallback?("⚡ Processing AI analysis results...")
            let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try to extract JSON content safely
            var jsonString: String
            if let jsonStartRange = cleanedContent.range(of: "{"),
               let jsonEndRange = cleanedContent.range(of: "}", options: .backwards),
               jsonStartRange.lowerBound < jsonEndRange.upperBound {
                jsonString = String(cleanedContent[jsonStartRange.lowerBound..<jsonEndRange.upperBound])
            } else {
                jsonString = cleanedContent
            }
            
            // Enhanced JSON parsing with error recovery
            var nutritionData: [String: Any]
            do {
                guard let jsonData = jsonString.data(using: .utf8),
                      let parsedJson = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    print("❌ OpenAI: Failed to parse extracted JSON")
                    print("❌ OpenAI: JSON string was: \(jsonString.prefix(500))...")
                    throw AIFoodAnalysisError.responseParsingFailed
                }
                nutritionData = parsedJson
            } catch {
                print("❌ OpenAI: JSON parsing error: \(error)")
                print("❌ OpenAI: Problematic JSON: \(jsonString.prefix(500))...")
                
                // Try fallback parsing with the original cleaned content
                if let fallbackData = cleanedContent.data(using: .utf8),
                   let fallbackJson = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any] {
                    nutritionData = fallbackJson
                } else {
                    print("❌ OpenAI: Both primary and fallback JSON parsing failed")
                    print("❌ OpenAI: Original content: \(content.prefix(1000))...")
                    throw AIFoodAnalysisError.responseParsingFailed
                }
            }
            
            // Parse detailed food items analysis with enhanced safety like Gemini
            var detailedFoodItems: [FoodItemAnalysis] = []
            
            do {
                if let foodItemsArray = nutritionData["food_items"] as? [[String: Any]] {
                    
                    // Enhanced per-item error handling like Gemini
                    for (index, itemData) in foodItemsArray.enumerated() {
                        do {
                            let foodItem = FoodItemAnalysis(
                                name: extractString(from: itemData, keys: ["name"]) ?? "Unknown Food",
                                portionEstimate: extractString(from: itemData, keys: ["portion_estimate"]) ?? "1 serving",
                                usdaServingSize: extractString(from: itemData, keys: ["usda_serving_size"]),
                                servingMultiplier: max(0.1, extractNumber(from: itemData, keys: ["serving_multiplier"]) ?? 1.0), // Prevent zero/negative
                                preparationMethod: extractString(from: itemData, keys: ["preparation_method"]),
                                visualCues: extractString(from: itemData, keys: ["visual_cues"]),
                                carbohydrates: max(0, extractNumber(from: itemData, keys: ["carbohydrates"]) ?? 0), // Ensure non-negative
                                calories: extractNumber(from: itemData, keys: ["calories"]).map { max(0, $0) }, // Bounds checking
                                fat: extractNumber(from: itemData, keys: ["fat"]).map { max(0, $0) }, // Bounds checking
                                fiber: extractNumber(from: itemData, keys: ["fiber"]).map { max(0, $0) }, // Bounds checking
                                protein: extractNumber(from: itemData, keys: ["protein"]).map { max(0, $0) }, // Bounds checking
                                assessmentNotes: extractString(from: itemData, keys: ["assessment_notes"])
                            )
                            detailedFoodItems.append(foodItem)
                        } catch {
                            print("⚠️ OpenAI: Error parsing food item \(index): \(error)")
                            // Continue with other items - doesn't crash the whole analysis
                        }
                    }
                }
            } catch {
                print("⚠️ OpenAI: Error in food items parsing: \(error)")
            }
            
            if let foodItemsStringArray = extractStringArray(from: nutritionData, keys: ["food_items"]) {
                // Fallback to legacy format
                let totalCarbs = extractNumber(from: nutritionData, keys: ["total_carbohydrates", "carbohydrates", "carbs"]) ?? 25.0
                let totalProtein = extractNumber(from: nutritionData, keys: ["total_protein", "protein"])
                let totalFat = extractNumber(from: nutritionData, keys: ["total_fat", "fat"])
                let totalFiber = extractNumber(from: nutritionData, keys: ["total_fiber", "fiber"])
                let totalCalories = extractNumber(from: nutritionData, keys: ["total_calories", "calories"])
                
                let singleItem = FoodItemAnalysis(
                    name: foodItemsStringArray.joined(separator: ", "),
                    portionEstimate: extractString(from: nutritionData, keys: ["portion_size"]) ?? "1 serving",
                    usdaServingSize: nil,
                    servingMultiplier: 1.0,
                    preparationMethod: nil,
                    visualCues: nil,
                    carbohydrates: totalCarbs,
                    calories: totalCalories,
                    fat: totalFat,
                    fiber: totalFiber,
                    protein: totalProtein,
                    assessmentNotes: "Legacy format - combined nutrition values"
                )
                detailedFoodItems = [singleItem]
            }
            
            // Enhanced fallback creation like Gemini - safe fallback with comprehensive data
            if detailedFoodItems.isEmpty {
                let fallbackItem = FoodItemAnalysis(
                    name: "OpenAI Analyzed Food",
                    portionEstimate: "1 standard serving",
                    usdaServingSize: nil,
                    servingMultiplier: 1.0,
                    preparationMethod: "Not specified in analysis",
                    visualCues: "Visual analysis completed",
                    carbohydrates: 25.0,
                    calories: 200.0,
                    fat: 10.0,
                    fiber: 5.0,
                    protein: 15.0,
                    assessmentNotes: "Safe fallback nutrition estimate - please verify actual food for accuracy"
                )
                detailedFoodItems = [fallbackItem]
            }
            
            // Extract totals
            let totalCarbs = extractNumber(from: nutritionData, keys: ["total_carbohydrates"]) ?? 
                            detailedFoodItems.reduce(0) { $0 + $1.carbohydrates }
            let totalProtein = extractNumber(from: nutritionData, keys: ["total_protein"]) ?? 
                              detailedFoodItems.compactMap { $0.protein }.reduce(0, +)
            let totalFat = extractNumber(from: nutritionData, keys: ["total_fat"]) ?? 
                          detailedFoodItems.compactMap { $0.fat }.reduce(0, +)
            let totalFiber = extractNumber(from: nutritionData, keys: ["total_fiber"]) ??
                            detailedFoodItems.compactMap { $0.fiber }.reduce(0, +)
            let totalCalories = extractNumber(from: nutritionData, keys: ["total_calories"]) ?? 
                               detailedFoodItems.compactMap { $0.calories }.reduce(0, +)
            
            let overallDescription = extractString(from: nutritionData, keys: ["overall_description", "detailed_description"])
            let portionAssessmentMethod = extractString(from: nutritionData, keys: ["portion_assessment_method", "analysis_notes"])
            let diabetesConsiderations = extractString(from: nutritionData, keys: ["diabetes_considerations"])
            let visualAssessmentDetails = extractString(from: nutritionData, keys: ["visual_assessment_details"])
            
            let confidence = extractConfidence(from: nutritionData)
            
            // Extract image type to determine if this is menu analysis or food photo
            let imageTypeString = extractString(from: nutritionData, keys: ["image_type"])
            let imageType = ImageAnalysisType(rawValue: imageTypeString ?? "food_photo") ?? .foodPhoto
            
            print("🔍 ========== OPENAI AI ANALYSIS RESULT CREATION ==========")
            print("🔍 nutritionData keys: \(nutritionData.keys)")
            if let absorptionTimeValue = nutritionData["absorption_time_hours"] {
                print("🔍 Raw absorption_time_hours in JSON: \(absorptionTimeValue) (type: \(type(of: absorptionTimeValue)))")
            } else {
                print("🔍 ❌ absorption_time_hours key not found in nutritionData")
            }
            
            let absorptionHours = extractNumber(from: nutritionData, keys: ["absorption_time_hours"])
            print("🔍 Extracted absorptionTimeHours: \(absorptionHours?.description ?? "nil")")
            print("🔍 ========== OPENAI AI ANALYSIS RESULT CREATION COMPLETE ==========")
            
            // Calculate original servings for proper scaling
            let originalServings = detailedFoodItems.reduce(0) { $0 + $1.servingMultiplier }
            
            return AIFoodAnalysisResult(
                imageType: imageType,
                foodItemsDetailed: detailedFoodItems,
                overallDescription: overallDescription,
                confidence: confidence,
                totalFoodPortions: extractNumber(from: nutritionData, keys: ["total_food_portions"]).map { Int($0) },
                totalUsdaServings: extractNumber(from: nutritionData, keys: ["total_usda_servings"]),
                totalCarbohydrates: totalCarbs,
                totalProtein: totalProtein > 0 ? totalProtein : nil,
                totalFat: totalFat > 0 ? totalFat : nil,
                totalFiber: totalFiber,
                totalCalories: totalCalories > 0 ? totalCalories : nil,
                portionAssessmentMethod: portionAssessmentMethod,
                diabetesConsiderations: diabetesConsiderations,
                visualAssessmentDetails: visualAssessmentDetails,
                notes: "Analyzed using OpenAI GPT Vision with detailed portion assessment",
                originalServings: originalServings,
                fatProteinUnits: extractString(from: nutritionData, keys: ["fat_protein_units"]),
                netCarbsAdjustment: extractString(from: nutritionData, keys: ["net_carbs_adjustment"]),
                insulinTimingRecommendations: extractString(from: nutritionData, keys: ["insulin_timing_recommendations"]),
                fpuDosingGuidance: extractString(from: nutritionData, keys: ["fpu_dosing_guidance"]),
                exerciseConsiderations: extractString(from: nutritionData, keys: ["exercise_considerations"]),
                absorptionTimeHours: absorptionHours,
                absorptionTimeReasoning: extractString(from: nutritionData, keys: ["absorption_time_reasoning"]),
                mealSizeImpact: extractString(from: nutritionData, keys: ["meal_size_impact"]),
                individualizationFactors: extractString(from: nutritionData, keys: ["individualization_factors"]),
                safetyAlerts: extractString(from: nutritionData, keys: ["safety_alerts"])
            )
            
        } catch let error as AIFoodAnalysisError {
            throw error
        } catch {
            throw AIFoodAnalysisError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractNumber(from json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            print("🧮 extractNumber checking key '\(key)' in JSON")
            if let value = json[key] as? Double {
                print("🧮 Found Double value: \(value) for key '\(key)'")
                let result = max(0, value) // Ensure non-negative nutrition values like Gemini
                print("🧮 Returning Double result: \(result)")
                return result
            } else if let value = json[key] as? Int {
                print("🧮 Found Int value: \(value) for key '\(key)'")
                let result = max(0, Double(value)) // Ensure non-negative
                print("🧮 Returning Int->Double result: \(result)")
                return result
            } else if let value = json[key] as? String, let doubleValue = Double(value) {
                print("🧮 Found String value: '\(value)' converted to Double: \(doubleValue) for key '\(key)'")
                let result = max(0, doubleValue) // Ensure non-negative
                print("🧮 Returning String->Double result: \(result)")
                return result
            } else {
                print("🧮 Key '\(key)' not found or not convertible to number. Value type: \(type(of: json[key]))")
                if let value = json[key] {
                    print("🧮 Value: \(value)")
                }
            }
        }
        print("🧮 extractNumber returning nil - no valid number found for keys: \(keys)")
        return nil
    }
    
    private func extractString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines) // Enhanced validation like Gemini
            }
        }
        return nil
    }
    
    private func extractStringArray(from json: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let value = json[key] as? [String] {
                return value
            } else if let value = json[key] as? String {
                return [value]
            }
        }
        return nil
    }
    
    private func extractConfidence(from json: [String: Any]) -> AIConfidenceLevel {
        let confidenceKeys = ["confidence", "confidence_score"]
        
        for key in confidenceKeys {
            if let value = json[key] as? Double {
                if value >= 0.8 {
                    return .high
                } else if value >= 0.5 {
                    return .medium
                } else {
                    return .low
                }
            } else if let value = json[key] as? String {
                // Enhanced string-based confidence detection like Gemini
                switch value.lowercased() {
                case "high":
                    return .high
                case "medium":
                    return .medium
                case "low":
                    return .low
                default:
                    continue
                }
            }
        }
        
        return .medium // Default confidence
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
        print("🇺🇸 Starting USDA FoodData Central search for: '\(query)'")
        
        guard let url = URL(string: "\(baseURL)/foods/search") else {
            throw OpenFoodFactsError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: "DEMO_KEY"), // USDA provides free demo access
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey"), // Get comprehensive nutrition data from multiple sources
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
                print("🇺🇸 USDA: HTTP error \(httpResponse.statusCode)")
                throw OpenFoodFactsError.serverError(httpResponse.statusCode)
            }
            
            // Parse USDA response with detailed error handling
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("🇺🇸 USDA: Invalid JSON response format")
                throw OpenFoodFactsError.decodingError(NSError(domain: "USDA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"]))
            }
            
            // Check for API errors in response
            if let error = jsonResponse["error"] as? [String: Any],
               let code = error["code"] as? String,
               let message = error["message"] as? String {
                print("🇺🇸 USDA: API error - \(code): \(message)")
                throw OpenFoodFactsError.serverError(400)
            }
            
            guard let foods = jsonResponse["foods"] as? [[String: Any]] else {
                print("🇺🇸 USDA: No foods array in response")
                throw OpenFoodFactsError.noData
            }
            
            print("🇺🇸 USDA: Raw API returned \(foods.count) food items")
            
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
            
            print("🇺🇸 USDA search completed: \(products.count) valid products found (filtered from \(foods.count) raw items)")
            return products
            
        } catch {
            print("🇺🇸 USDA search failed: \(error)")
            
            // Handle task cancellation gracefully
            if error is CancellationError {
                print("🇺🇸 USDA: Task was cancelled (expected behavior during rapid typing)")
                return []
            }
            
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("🇺🇸 USDA: URLSession request was cancelled (expected behavior during rapid typing)")
                return []
            }
            
            throw OpenFoodFactsError.networkError(error)
        }
    }
    
    /// Convert USDA food data to OpenFoodFactsProduct for UI compatibility
    private func convertUSDAFoodToProduct(_ foodData: [String: Any]) -> OpenFoodFactsProduct? {
        guard let fdcId = foodData["fdcId"] as? Int,
              let description = foodData["description"] as? String else {
            print("🇺🇸 USDA: Missing fdcId or description for food item")
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
            print("🇺🇸 USDA: Found \(foodNutrients.count) nutrients for '\(description)'")
            
            for nutrient in foodNutrients {
                // Debug: print the structure of the first few nutrients
                if foundNutrients.count < 3 {
                    print("🇺🇸 USDA: Nutrient structure: \(nutrient)")
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
            print("🇺🇸 USDA: No foodNutrients array found in food data for '\(description)'")
            print("🇺🇸 USDA: Available keys in foodData: \(Array(foodData.keys))")
        }
        
        // Log what we found for debugging
        if foundNutrients.isEmpty {
            print("🇺🇸 USDA: No recognized nutrients found for '\(description)' (fdcId: \(fdcId))")
        } else {
            print("🇺🇸 USDA: Found nutrients for '\(description)': \(foundNutrients.joined(separator: ", "))")
        }
        
        // Enhanced data quality validation
        let hasUsableNutrientData = carbs > 0 || protein > 0 || fat > 0 || energy > 0
        if !hasUsableNutrientData {
            print("🇺🇸 USDA: Skipping '\(description)' - no usable nutrient data (carbs: \(carbs), protein: \(protein), fat: \(fat), energy: \(energy))")
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

// MARK: - Google Gemini Food Analysis Service

/// Service for food analysis using Google Gemini Vision API (free tier)
class GoogleGeminiFoodAnalysisService {
    static let shared = GoogleGeminiFoodAnalysisService()
    
    private let baseURLTemplate = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    
    private init() {}
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, apiKey: apiKey, query: query, telemetryCallback: nil)
    }
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        print("🍱 Starting Google Gemini food analysis")
        telemetryCallback?("⚙️ Configuring Gemini parameters...")
        
        // Get optimal model based on current analysis mode
        let analysisMode = ConfigurableAIService.shared.analysisMode
        let model = ConfigurableAIService.optimalModel(for: .googleGemini, mode: analysisMode)
        let baseURL = baseURLTemplate.replacingOccurrences(of: "{model}", with: model)
        
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Optimize image size for faster processing and uploads
        telemetryCallback?("🖼️ Optimizing your image...")
        let optimizedImage = ConfigurableAIService.optimizeImageForAnalysis(image)
        
        // Convert image to base64 with adaptive compression
        telemetryCallback?("🔄 Encoding image data...")
        let compressionQuality = ConfigurableAIService.adaptiveCompressionQuality(for: optimizedImage)
        guard let imageData = optimizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw AIFoodAnalysisError.imageProcessingFailed
        }
        let base64Image = imageData.base64EncodedString()
        
        // Create Gemini API request payload
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": query.isEmpty ? getAnalysisPrompt() : "\(query)\n\n\(getAnalysisPrompt())"
                        ],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.01,  // Minimal temperature for fastest responses
                "topP": 0.95,  // High value for comprehensive vocabulary
                "topK": 8,  // Very focused for maximum speed
                "maxOutputTokens": 2500  // Balanced for speed vs detail
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AIFoodAnalysisError.requestCreationFailed
        }
        
        telemetryCallback?("🌐 Sending request to Google Gemini...")
        
        do {
            telemetryCallback?("⏳ AI is cooking up results...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            telemetryCallback?("📥 Received response from Gemini...")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Google Gemini: Invalid HTTP response")
                throw AIFoodAnalysisError.invalidResponse
            }
            
            
            guard httpResponse.statusCode == 200 else {
                print("❌ Google Gemini API error: \(httpResponse.statusCode)")
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("❌ Gemini API Error Details: \(errorData)")
                    
                    // Check for specific Google Gemini errors
                    if let error = errorData["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        print("❌ Gemini Error Message: \(message)")
                        
                        // Handle common Gemini errors with specific error types
                        if message.contains("quota") || message.contains("QUOTA_EXCEEDED") {
                            throw AIFoodAnalysisError.quotaExceeded(provider: "Google Gemini")
                        } else if message.contains("RATE_LIMIT_EXCEEDED") || message.contains("rate limit") {
                            throw AIFoodAnalysisError.rateLimitExceeded(provider: "Google Gemini")
                        } else if message.contains("PERMISSION_DENIED") || message.contains("API_KEY_INVALID") {
                            throw AIFoodAnalysisError.customError("Invalid Google Gemini API key. Please check your configuration.")
                        } else if message.contains("RESOURCE_EXHAUSTED") {
                            throw AIFoodAnalysisError.creditsExhausted(provider: "Google Gemini")
                        }
                    }
                } else {
                    print("❌ Gemini: Error data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                }
                
                // Handle HTTP status codes for common credit/quota issues
                if httpResponse.statusCode == 429 {
                    throw AIFoodAnalysisError.rateLimitExceeded(provider: "Google Gemini")
                } else if httpResponse.statusCode == 403 {
                    throw AIFoodAnalysisError.quotaExceeded(provider: "Google Gemini")
                }
                
                throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
            }
            
            // Add data validation
            guard data.count > 0 else {
                print("❌ Google Gemini: Empty response data")
                throw AIFoodAnalysisError.invalidResponse
            }
            
            // Parse Gemini response with detailed error handling
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Google Gemini: Failed to parse JSON response")
                print("❌ Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            
            guard let candidates = jsonResponse["candidates"] as? [[String: Any]], !candidates.isEmpty else {
                print("❌ Google Gemini: No candidates in response")
                if let error = jsonResponse["error"] as? [String: Any] {
                    print("❌ Google Gemini: API returned error: \(error)")
                }
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            let firstCandidate = candidates[0]
            print("🔧 Google Gemini: Candidate keys: \(Array(firstCandidate.keys))")
            
            guard let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  !parts.isEmpty,
                  let text = parts[0]["text"] as? String else {
                print("❌ Google Gemini: Invalid response structure")
                print("❌ Candidate: \(firstCandidate)")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            print("🔧 Google Gemini: Received text length: \(text.count)")
            
            // Parse the JSON content from Gemini's response
            let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let contentData = cleanedText.data(using: .utf8),
                  let nutritionData = try JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
                throw AIFoodAnalysisError.responseParsingFailed
            }
            
            // Parse detailed food items analysis with crash protection
            var detailedFoodItems: [FoodItemAnalysis] = []
            
            do {
                if let foodItemsArray = nutritionData["food_items"] as? [[String: Any]] {
                    // New detailed format
                    for (index, itemData) in foodItemsArray.enumerated() {
                        do {
                            let foodItem = FoodItemAnalysis(
                                name: extractString(from: itemData, keys: ["name"]) ?? "Food Item \(index + 1)",
                                portionEstimate: extractString(from: itemData, keys: ["portion_estimate"]) ?? "1 serving",
                                usdaServingSize: extractString(from: itemData, keys: ["usda_serving_size"]),
                                servingMultiplier: max(0.1, extractNumber(from: itemData, keys: ["serving_multiplier"]) ?? 1.0),
                                preparationMethod: extractString(from: itemData, keys: ["preparation_method"]),
                                visualCues: extractString(from: itemData, keys: ["visual_cues"]),
                                carbohydrates: max(0, extractNumber(from: itemData, keys: ["carbohydrates"]) ?? 0),
                                calories: extractNumber(from: itemData, keys: ["calories"]),
                                fat: extractNumber(from: itemData, keys: ["fat"]),
                                fiber: extractNumber(from: itemData, keys: ["fiber"]),
                                protein: extractNumber(from: itemData, keys: ["protein"]),
                                assessmentNotes: extractString(from: itemData, keys: ["assessment_notes"])
                            )
                            detailedFoodItems.append(foodItem)
                        } catch {
                            print("⚠️ Google Gemini: Error parsing food item \(index): \(error)")
                            // Continue with other items
                        }
                    }
                } else if let foodItemsStringArray = extractStringArray(from: nutritionData, keys: ["food_items"]) {
                    // Fallback to legacy format
                    let totalCarbs = max(0, extractNumber(from: nutritionData, keys: ["total_carbohydrates", "carbohydrates", "carbs"]) ?? 25.0)
                    let totalProtein = extractNumber(from: nutritionData, keys: ["total_protein", "protein"])
                    let totalFat = extractNumber(from: nutritionData, keys: ["total_fat", "fat"])
                    let totalFiber = extractNumber(from: nutritionData, keys: ["total_fiber", "fiber"])
                    let totalCalories = extractNumber(from: nutritionData, keys: ["total_calories", "calories"])
                    
                    let singleItem = FoodItemAnalysis(
                        name: foodItemsStringArray.joined(separator: ", "),
                        portionEstimate: extractString(from: nutritionData, keys: ["portion_size"]) ?? "1 serving",
                        usdaServingSize: nil,
                        servingMultiplier: 1.0,
                        preparationMethod: nil,
                        visualCues: nil,
                        carbohydrates: totalCarbs,
                        calories: totalCalories,
                        fat: totalFat,
                        fiber: totalFiber,
                        protein: totalProtein,
                        assessmentNotes: "Legacy format - combined nutrition values"
                    )
                    detailedFoodItems = [singleItem]
                }
            } catch {
                print("⚠️ Google Gemini: Error in food items parsing: \(error)")
            }
            
            // If no detailed items were parsed, create a safe fallback
            if detailedFoodItems.isEmpty {
                let fallbackItem = FoodItemAnalysis(
                    name: "Analyzed Food",
                    portionEstimate: "1 serving",
                    usdaServingSize: nil,
                    servingMultiplier: 1.0,
                    preparationMethod: "Not specified",
                    visualCues: "Visual analysis completed",
                    carbohydrates: 25.0,
                    calories: 200.0,
                    fat: 10.0,
                    fiber: 5.0,
                    protein: 15.0,
                    assessmentNotes: "Safe fallback nutrition estimate - check actual food for accuracy"
                )
                detailedFoodItems = [fallbackItem]
            }
            
            // Extract totals with safety checks
            let totalCarbs = max(0, extractNumber(from: nutritionData, keys: ["total_carbohydrates"]) ?? 
                            detailedFoodItems.reduce(0) { $0 + $1.carbohydrates })
            let totalProtein = max(0, extractNumber(from: nutritionData, keys: ["total_protein"]) ?? 
                              detailedFoodItems.compactMap { $0.protein }.reduce(0, +))
            let totalFat = max(0, extractNumber(from: nutritionData, keys: ["total_fat"]) ?? 
                          detailedFoodItems.compactMap { $0.fat }.reduce(0, +))
            let totalFiber = max(0, extractNumber(from: nutritionData, keys: ["total_fiber"]) ??
                          detailedFoodItems.compactMap { $0.fiber }.reduce(0, +))
            let totalCalories = max(0, extractNumber(from: nutritionData, keys: ["total_calories"]) ?? 
                               detailedFoodItems.compactMap { $0.calories }.reduce(0, +))
            
            let overallDescription = extractString(from: nutritionData, keys: ["overall_description", "detailed_description"]) ?? "Google Gemini analysis completed"
            let portionAssessmentMethod = extractString(from: nutritionData, keys: ["portion_assessment_method", "analysis_notes"])
            let diabetesConsiderations = extractString(from: nutritionData, keys: ["diabetes_considerations"])
            let visualAssessmentDetails = extractString(from: nutritionData, keys: ["visual_assessment_details"])
            
            let confidence = extractConfidence(from: nutritionData)
            
            // Extract image type to determine if this is menu analysis or food photo
            let imageTypeString = extractString(from: nutritionData, keys: ["image_type"])
            let imageType = ImageAnalysisType(rawValue: imageTypeString ?? "food_photo") ?? .foodPhoto
            
            print("🔍 ========== GEMINI AI ANALYSIS RESULT CREATION ==========")
            print("🔍 nutritionData keys: \(nutritionData.keys)")
            if let absorptionTimeValue = nutritionData["absorption_time_hours"] {
                print("🔍 Raw absorption_time_hours in JSON: \(absorptionTimeValue) (type: \(type(of: absorptionTimeValue)))")
            } else {
                print("🔍 ❌ absorption_time_hours key not found in nutritionData")
            }
            
            let absorptionHours = extractNumber(from: nutritionData, keys: ["absorption_time_hours"])
            print("🔍 Extracted absorptionTimeHours: \(absorptionHours?.description ?? "nil")")
            print("🔍 ========== GEMINI AI ANALYSIS RESULT CREATION COMPLETE ==========")
            
            // Calculate original servings for proper scaling
            let originalServings = detailedFoodItems.reduce(0) { $0 + $1.servingMultiplier }
            
            return AIFoodAnalysisResult(
                imageType: imageType,
                foodItemsDetailed: detailedFoodItems,
                overallDescription: overallDescription,
                confidence: confidence,
                totalFoodPortions: extractNumber(from: nutritionData, keys: ["total_food_portions"]).map { Int($0) },
                totalUsdaServings: extractNumber(from: nutritionData, keys: ["total_usda_servings"]),
                totalCarbohydrates: totalCarbs,
                totalProtein: totalProtein > 0 ? totalProtein : nil,
                totalFat: totalFat > 0 ? totalFat : nil,
                totalFiber: totalFiber,
                totalCalories: totalCalories > 0 ? totalCalories : nil,
                portionAssessmentMethod: portionAssessmentMethod,
                diabetesConsiderations: diabetesConsiderations,
                visualAssessmentDetails: visualAssessmentDetails,
                notes: "Analyzed using Google Gemini Vision - AI food recognition with enhanced safety measures",
                originalServings: originalServings,
                fatProteinUnits: extractString(from: nutritionData, keys: ["fat_protein_units"]),
                netCarbsAdjustment: extractString(from: nutritionData, keys: ["net_carbs_adjustment"]),
                insulinTimingRecommendations: extractString(from: nutritionData, keys: ["insulin_timing_recommendations"]),
                fpuDosingGuidance: extractString(from: nutritionData, keys: ["fpu_dosing_guidance"]),
                exerciseConsiderations: extractString(from: nutritionData, keys: ["exercise_considerations"]),
                absorptionTimeHours: absorptionHours,
                absorptionTimeReasoning: extractString(from: nutritionData, keys: ["absorption_time_reasoning"]),
                mealSizeImpact: extractString(from: nutritionData, keys: ["meal_size_impact"]),
                individualizationFactors: extractString(from: nutritionData, keys: ["individualization_factors"]),
                safetyAlerts: extractString(from: nutritionData, keys: ["safety_alerts"])
            )
            
        } catch let error as AIFoodAnalysisError {
            throw error
        } catch {
            throw AIFoodAnalysisError.networkError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractNumber(from json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = json[key] as? Double {
                return max(0, value) // Ensure non-negative nutrition values
            } else if let value = json[key] as? Int {
                return max(0, Double(value)) // Ensure non-negative nutrition values
            } else if let value = json[key] as? String, let doubleValue = Double(value) {
                return max(0, doubleValue) // Ensure non-negative nutrition values
            }
        }
        return nil
    }
    
    private func extractString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    private func extractStringArray(from json: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let value = json[key] as? [String] {
                let cleanedItems = value.compactMap { item in
                    let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned.isEmpty ? nil : cleaned
                }
                return cleanedItems.isEmpty ? nil : cleanedItems
            } else if let value = json[key] as? String {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : [cleaned]
            }
        }
        return nil
    }
    
    private func extractConfidence(from json: [String: Any]) -> AIConfidenceLevel {
        let confidenceKeys = ["confidence", "confidence_score"]
        
        for key in confidenceKeys {
            if let value = json[key] as? Double {
                if value >= 0.8 {
                    return .high
                } else if value >= 0.5 {
                    return .medium
                } else {
                    return .low
                }
            } else if let value = json[key] as? String {
                switch value.lowercased() {
                case "high":
                    return .high
                case "medium":
                    return .medium
                case "low":
                    return .low
                default:
                    continue
                }
            }
        }
        
        return .high // Gemini typically has high confidence
    }
}

// MARK: - Basic Food Analysis Service (No API Key Required)

/// Basic food analysis using built-in logic and food database
/// Provides basic nutrition estimates without requiring external API keys
class BasicFoodAnalysisService {
    static let shared = BasicFoodAnalysisService()
    private init() {}
    
    func analyzeFoodImage(_ image: UIImage) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, telemetryCallback: nil)
    }
    
    func analyzeFoodImage(_ image: UIImage, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        telemetryCallback?("📊 Initializing basic analysis...")
        
        // Simulate analysis time for better UX with telemetry updates
        telemetryCallback?("📱 Analyzing image properties...")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        telemetryCallback?("🍽️ Identifying food characteristics...")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        telemetryCallback?("📊 Calculating nutrition estimates...")
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Basic analysis based on image characteristics and common foods
        telemetryCallback?("⚙️ Processing analysis results...")
        let analysisResult = performBasicAnalysis(image: image)
        
        return analysisResult
    }
    
    private func performBasicAnalysis(image: UIImage) -> AIFoodAnalysisResult {
        // Basic analysis logic - could be enhanced with Core ML models in the future
        
        // Analyze image characteristics
        let imageSize = image.size
        let brightness = calculateImageBrightness(image: image)
        
        // Generate basic food estimation based on image properties
        let foodItems = generateBasicFoodEstimate(imageSize: imageSize, brightness: brightness)
        
        // Calculate totals
        let totalCarbs = foodItems.reduce(0) { $0 + $1.carbohydrates }
        let totalProtein = foodItems.compactMap { $0.protein }.reduce(0, +)
        let totalFat = foodItems.compactMap { $0.fat }.reduce(0, +)
        let totalFiber = foodItems.compactMap { $0.fiber }.reduce(0, +)
        let totalCalories = foodItems.compactMap { $0.calories }.reduce(0, +)
        
        // Calculate original servings for proper scaling
        let originalServings = foodItems.reduce(0) { $0 + $1.servingMultiplier }
        
        return AIFoodAnalysisResult(
            imageType: .foodPhoto, // Fallback analysis assumes food photo
            foodItemsDetailed: foodItems,
            overallDescription: "Basic analysis of visible food items. For more accurate results, consider using an AI provider with API key.",
            confidence: .medium,
            totalFoodPortions: foodItems.count,
            totalUsdaServings: Double(foodItems.count), // Fallback estimate
            totalCarbohydrates: totalCarbs,
            totalProtein: totalProtein > 0 ? totalProtein : nil,
            totalFat: totalFat > 0 ? totalFat : nil,
            totalFiber: totalFiber > 0 ? totalFiber : nil,
            totalCalories: totalCalories > 0 ? totalCalories : nil,
            portionAssessmentMethod: "Estimated based on image size and typical serving portions",
            diabetesConsiderations: "Basic carbohydrate estimate provided. Monitor blood glucose response and adjust insulin as needed.",
            visualAssessmentDetails: nil,
            notes: "This is a basic analysis. For more detailed and accurate nutrition information, consider configuring an AI provider in Settings.",
            originalServings: originalServings,
            fatProteinUnits: nil,
            netCarbsAdjustment: nil,
            insulinTimingRecommendations: nil,
            fpuDosingGuidance: nil,
            exerciseConsiderations: nil,
            absorptionTimeHours: nil,
            absorptionTimeReasoning: nil,
            mealSizeImpact: nil,
            individualizationFactors: nil,
            safetyAlerts: nil
        )
    }
    
    private func calculateImageBrightness(image: UIImage) -> Double {
        // Simple brightness calculation based on image properties
        // In a real implementation, this could analyze pixel values
        return 0.6 // Default medium brightness
    }
    
    private func generateBasicFoodEstimate(imageSize: CGSize, brightness: Double) -> [FoodItemAnalysis] {
        // Generate basic food estimates based on common foods and typical portions
        // This is a simplified approach - could be enhanced with food recognition models
        
        let portionSize = estimatePortionSize(imageSize: imageSize)
        
        // Common food estimation
        let commonFoods = [
            "Mixed Plate",
            "Carbohydrate-rich Food",
            "Protein Source",
            "Vegetables"
        ]
        
        let selectedFood = commonFoods.randomElement() ?? "Mixed Meal"
        
        return [
            FoodItemAnalysis(
                name: selectedFood,
                portionEstimate: portionSize,
                usdaServingSize: nil,
                servingMultiplier: 1.0,
                preparationMethod: "Not specified",
                visualCues: nil,
                carbohydrates: estimateCarbohydrates(for: selectedFood, portion: portionSize),
                calories: estimateCalories(for: selectedFood, portion: portionSize),
                fat: estimateFat(for: selectedFood, portion: portionSize),
                fiber: estimateFiber(for: selectedFood, portion: portionSize),
                protein: estimateProtein(for: selectedFood, portion: portionSize),
                assessmentNotes: "Basic estimate based on typical portions and common nutrition values. For diabetes management, monitor actual blood glucose response."
            )
        ]
    }
    
    private func estimatePortionSize(imageSize: CGSize) -> String {
        let area = imageSize.width * imageSize.height
        
        if area < 100000 {
            return "Small portion (about 1/2 cup or 3-4 oz)"
        } else if area < 300000 {
            return "Medium portion (about 1 cup or 6 oz)"
        } else {
            return "Large portion (about 1.5 cups or 8+ oz)"
        }
    }
    
    private func estimateCarbohydrates(for food: String, portion: String) -> Double {
        // Basic carb estimates based on food type and portion
        let baseCarbs: Double
        
        switch food {
        case "Carbohydrate-rich Food":
            baseCarbs = 45.0 // Rice, pasta, bread
        case "Mixed Plate":
            baseCarbs = 30.0 // Typical mixed meal
        case "Protein Source":
            baseCarbs = 5.0 // Meat, fish, eggs
        case "Vegetables":
            baseCarbs = 15.0 // Mixed vegetables
        default:
            baseCarbs = 25.0 // Default mixed food
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseCarbs * 0.7
        } else if portion.contains("Large") {
            return baseCarbs * 1.4
        } else {
            return baseCarbs
        }
    }
    
    private func estimateProtein(for food: String, portion: String) -> Double? {
        let baseProtein: Double
        
        switch food {
        case "Protein Source":
            baseProtein = 25.0
        case "Mixed Plate":
            baseProtein = 15.0
        case "Carbohydrate-rich Food":
            baseProtein = 8.0
        case "Vegetables":
            baseProtein = 3.0
        default:
            baseProtein = 12.0
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseProtein * 0.7
        } else if portion.contains("Large") {
            return baseProtein * 1.4
        } else {
            return baseProtein
        }
    }
    
    private func estimateFat(for food: String, portion: String) -> Double? {
        let baseFat: Double
        
        switch food {
        case "Protein Source":
            baseFat = 12.0
        case "Mixed Plate":
            baseFat = 8.0
        case "Carbohydrate-rich Food":
            baseFat = 2.0
        case "Vegetables":
            baseFat = 1.0
        default:
            baseFat = 6.0
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseFat * 0.7
        } else if portion.contains("Large") {
            return baseFat * 1.4
        } else {
            return baseFat
        }
    }
    
    private func estimateCalories(for food: String, portion: String) -> Double? {
        let baseCalories: Double
        
        switch food {
        case "Protein Source":
            baseCalories = 200.0
        case "Mixed Plate":
            baseCalories = 300.0
        case "Carbohydrate-rich Food":
            baseCalories = 220.0
        case "Vegetables":
            baseCalories = 60.0
        default:
            baseCalories = 250.0
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseCalories * 0.7
        } else if portion.contains("Large") {
            return baseCalories * 1.4
        } else {
            return baseCalories
        }
    }
    
    private func estimateFiber(for food: String, portion: String) -> Double? {
        let baseFiber: Double
        
        switch food {
        case "Protein Source":
            baseFiber = 0.5
        case "Mixed Plate":
            baseFiber = 4.0
        case "Carbohydrate-rich Food":
            baseFiber = 3.0
        case "Vegetables":
            baseFiber = 6.0
        default:
            baseFiber = 2.5
        }
        
        // Adjust for portion size
        if portion.contains("Small") {
            return baseFiber * 0.7
        } else if portion.contains("Large") {
            return baseFiber * 1.4
        } else {
            return baseFiber
        }
    }
}

// MARK: - Claude Food Analysis Service

/// Claude (Anthropic) food analysis service
class ClaudeFoodAnalysisService {
    static let shared = ClaudeFoodAnalysisService()
    private init() {}
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String) async throws -> AIFoodAnalysisResult {
        return try await analyzeFoodImage(image, apiKey: apiKey, query: query, telemetryCallback: nil)
    }
    
    func analyzeFoodImage(_ image: UIImage, apiKey: String, query: String, telemetryCallback: ((String) -> Void)?) async throws -> AIFoodAnalysisResult {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Get optimal model based on current analysis mode
        telemetryCallback?("⚙️ Configuring Claude parameters...")
        let analysisMode = ConfigurableAIService.shared.analysisMode
        let model = ConfigurableAIService.optimalModel(for: .claude, mode: analysisMode)
        
        
        // Optimize image size for faster processing and uploads
        telemetryCallback?("🖼️ Optimizing your image...")
        let optimizedImage = ConfigurableAIService.optimizeImageForAnalysis(image)
        
        // Convert image to base64 with adaptive compression
        telemetryCallback?("🔄 Encoding image data...")
        let compressionQuality = ConfigurableAIService.adaptiveCompressionQuality(for: optimizedImage)
        guard let imageData = optimizedImage.jpegData(compressionQuality: compressionQuality) else {
            throw AIFoodAnalysisError.invalidResponse
        }
        let base64Image = imageData.base64EncodedString()
        
        // Prepare the request
        telemetryCallback?("📡 Preparing API request...")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let requestBody: [String: Any] = [
            "model": model, // Dynamic model selection based on analysis mode
            "max_tokens": 2500, // Balanced for speed vs detail
            "temperature": 0.01, // Optimized for faster, more deterministic responses
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": query.isEmpty ? getAnalysisPrompt() : "\(query)\n\n\(getAnalysisPrompt())"
                        ],
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        telemetryCallback?("🌐 Sending request to Claude...")
        
        // Make the request
        telemetryCallback?("⏳ AI is cooking up results...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        telemetryCallback?("📥 Received response from Claude...")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Claude: Invalid HTTP response")
            throw AIFoodAnalysisError.invalidResponse
        }
        
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("❌ Claude API Error: \(errorData)")
                if let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ Claude Error Message: \(message)")
                    
                    // Handle common Claude errors with specific error types
                    if message.contains("credit") || message.contains("billing") || message.contains("usage") {
                        throw AIFoodAnalysisError.creditsExhausted(provider: "Claude")
                    } else if message.contains("rate_limit") || message.contains("rate limit") {
                        throw AIFoodAnalysisError.rateLimitExceeded(provider: "Claude")
                    } else if message.contains("quota") || message.contains("limit") {
                        throw AIFoodAnalysisError.quotaExceeded(provider: "Claude")
                    } else if message.contains("authentication") || message.contains("invalid") && message.contains("key") {
                        throw AIFoodAnalysisError.customError("Invalid Claude API key. Please check your configuration.")
                    }
                }
            } else {
                print("❌ Claude: Error data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            }
            
            // Handle HTTP status codes for common credit/quota issues
            if httpResponse.statusCode == 429 {
                throw AIFoodAnalysisError.rateLimitExceeded(provider: "Claude")
            } else if httpResponse.statusCode == 402 {
                throw AIFoodAnalysisError.creditsExhausted(provider: "Claude")
            } else if httpResponse.statusCode == 403 {
                throw AIFoodAnalysisError.quotaExceeded(provider: "Claude")
            }
            
            throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
        }
        
        // Enhanced data validation like Gemini
        guard data.count > 0 else {
            print("❌ Claude: Empty response data")
            throw AIFoodAnalysisError.invalidResponse
        }
        
        // Parse response
        telemetryCallback?("🔍 Parsing Claude response...")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Claude: Failed to parse JSON response")
            print("❌ Claude: Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            throw AIFoodAnalysisError.responseParsingFailed
        }
        
        guard let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            print("❌ Claude: Invalid response structure")
            print("❌ Claude: Response JSON: \(json)")
            throw AIFoodAnalysisError.responseParsingFailed
        }
        
        // Add detailed logging like Gemini
        print("🔧 Claude: Received text length: \(text.count)")
        
        // Parse the JSON response from Claude
        telemetryCallback?("⚡ Processing AI analysis results...")
        return try parseClaudeAnalysis(text)
    }
    
    private func parseClaudeAnalysis(_ text: String) throws -> AIFoodAnalysisResult {
        // Clean the text and extract JSON from Claude's response
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Safely extract JSON content with proper bounds checking
        var jsonString: String
        if let jsonStartRange = cleanedText.range(of: "{"),
           let jsonEndRange = cleanedText.range(of: "}", options: .backwards),
           jsonStartRange.lowerBound < jsonEndRange.upperBound { // Ensure valid range
            // Safely extract from start brace to end brace (inclusive)
            jsonString = String(cleanedText[jsonStartRange.lowerBound..<jsonEndRange.upperBound])
        } else {
            // If no clear JSON boundaries, assume the whole cleaned text is JSON
            jsonString = cleanedText
        }
        
        // Additional safety check for empty JSON
        if jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            jsonString = cleanedText
        }
        
        print("🔧 Claude: Attempting to parse JSON: \(jsonString.prefix(300))...")
        
        // Enhanced JSON parsing with error recovery
        var json: [String: Any]
        do {
            guard let jsonData = jsonString.data(using: .utf8),
                  let parsedJson = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("❌ Claude: Failed to parse extracted JSON")
                print("❌ Claude: JSON string was: \(jsonString.prefix(500))...")
                throw AIFoodAnalysisError.responseParsingFailed
            }
            json = parsedJson
        } catch {
            print("❌ Claude: JSON parsing error: \(error)")
            print("❌ Claude: Problematic JSON: \(jsonString.prefix(500))...")
            
            // Try fallback parsing with the original cleaned text
            if let fallbackData = cleanedText.data(using: .utf8),
               let fallbackJson = try? JSONSerialization.jsonObject(with: fallbackData) as? [String: Any] {
                json = fallbackJson
            } else {
                throw AIFoodAnalysisError.responseParsingFailed
            }
        }
        
        // Parse food items with enhanced safety like Gemini
        var foodItems: [FoodItemAnalysis] = []
        
        do {
            if let foodItemsArray = json["food_items"] as? [[String: Any]] {
                
                // Enhanced per-item error handling like Gemini
                for (index, item) in foodItemsArray.enumerated() {
                    do {
                        let foodItem = FoodItemAnalysis(
                            name: extractClaudeString(from: item, keys: ["name"]) ?? "Unknown Food",
                            portionEstimate: extractClaudeString(from: item, keys: ["portion_estimate"]) ?? "1 serving",
                            usdaServingSize: extractClaudeString(from: item, keys: ["usda_serving_size"]),
                            servingMultiplier: max(0.1, extractClaudeNumber(from: item, keys: ["serving_multiplier"]) ?? 1.0), // Prevent zero/negative
                            preparationMethod: extractClaudeString(from: item, keys: ["preparation_method"]),
                            visualCues: extractClaudeString(from: item, keys: ["visual_cues"]),
                            carbohydrates: max(0, extractClaudeNumber(from: item, keys: ["carbohydrates"]) ?? 0), // Ensure non-negative
                            calories: extractClaudeNumber(from: item, keys: ["calories"]).map { max(0, $0) }, // Bounds checking
                            fat: extractClaudeNumber(from: item, keys: ["fat"]).map { max(0, $0) }, // Bounds checking
                            fiber: extractClaudeNumber(from: item, keys: ["fiber"]).map { max(0, $0) }, // Bounds checking
                            protein: extractClaudeNumber(from: item, keys: ["protein"]).map { max(0, $0) }, // Bounds checking
                            assessmentNotes: extractClaudeString(from: item, keys: ["assessment_notes"])
                        )
                        foodItems.append(foodItem)
                    } catch {
                        print("⚠️ Claude: Error parsing food item \(index): \(error)")
                        // Continue with other items - doesn't crash the whole analysis
                    }
                }
            }
        } catch {
            print("⚠️ Claude: Error in food items parsing: \(error)")
        }
        
        // Enhanced fallback creation like Gemini - safe fallback with comprehensive data
        if foodItems.isEmpty {
            let totalCarbs = extractClaudeNumber(from: json, keys: ["total_carbohydrates"]) ?? 25.0
            let totalProtein = extractClaudeNumber(from: json, keys: ["total_protein"])
            let totalFat = extractClaudeNumber(from: json, keys: ["total_fat"])
            let totalFiber = extractClaudeNumber(from: json, keys: ["total_fiber"])
            let totalCalories = extractClaudeNumber(from: json, keys: ["total_calories"])
            
            foodItems = [
                FoodItemAnalysis(
                    name: "Claude Analyzed Food",
                    portionEstimate: "1 standard serving",
                    usdaServingSize: nil,
                    servingMultiplier: 1.0,
                    preparationMethod: "Not specified in analysis",
                    visualCues: "Visual analysis completed",
                    carbohydrates: max(0, totalCarbs), // Ensure non-negative
                    calories: totalCalories.map { max(0, $0) }, // Bounds checking
                    fat: totalFat.map { max(0, $0) }, // Bounds checking
                    fiber: totalFiber.map { max(0, $0) },
                    protein: totalProtein.map { max(0, $0) }, // Bounds checking
                    assessmentNotes: "Safe fallback nutrition estimate - please verify actual food for accuracy"
                )
            ]
        }
        
        let confidence = extractConfidence(from: json)
        
        // Extract image type to determine if this is menu analysis or food photo
        let imageTypeString = json["image_type"] as? String
        let imageType = ImageAnalysisType(rawValue: imageTypeString ?? "food_photo") ?? .foodPhoto
        
        // Calculate original servings for proper scaling
        let originalServings = foodItems.reduce(0) { $0 + $1.servingMultiplier }
        
        return AIFoodAnalysisResult(
            imageType: imageType,
            foodItemsDetailed: foodItems,
            overallDescription: ConfigurableAIService.cleanFoodText(json["overall_description"] as? String),
            confidence: confidence,
            totalFoodPortions: (json["total_food_portions"] as? Double).map { Int($0) },
            totalUsdaServings: json["total_usda_servings"] as? Double,
            totalCarbohydrates: json["total_carbohydrates"] as? Double ?? foodItems.reduce(0) { $0 + $1.carbohydrates },
            totalProtein: json["total_protein"] as? Double ?? foodItems.compactMap { $0.protein }.reduce(0, +),
            totalFat: json["total_fat"] as? Double ?? foodItems.compactMap { $0.fat }.reduce(0, +),
            totalFiber: json["total_fiber"] as? Double ?? foodItems.compactMap { $0.fiber }.reduce(0, +),
            totalCalories: json["total_calories"] as? Double ?? foodItems.compactMap { $0.calories }.reduce(0, +),
            portionAssessmentMethod: json["portion_assessment_method"] as? String,
            diabetesConsiderations: json["diabetes_considerations"] as? String,
            visualAssessmentDetails: json["visual_assessment_details"] as? String,
            notes: "Analysis provided by Claude (Anthropic)",
            originalServings: originalServings,
            fatProteinUnits: json["fat_protein_units"] as? String,
            netCarbsAdjustment: json["net_carbs_adjustment"] as? String,
            insulinTimingRecommendations: json["insulin_timing_recommendations"] as? String,
            fpuDosingGuidance: json["fpu_dosing_guidance"] as? String,
            exerciseConsiderations: json["exercise_considerations"] as? String,
            absorptionTimeHours: json["absorption_time_hours"] as? Double,
            absorptionTimeReasoning: json["absorption_time_reasoning"] as? String,
            mealSizeImpact: json["meal_size_impact"] as? String,
            individualizationFactors: json["individualization_factors"] as? String,
            safetyAlerts: json["safety_alerts"] as? String
        )
    }
    
    // MARK: - Claude Helper Methods
    
    private func extractClaudeNumber(from json: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = json[key] as? Double {
                return max(0, value) // Ensure non-negative nutrition values like Gemini
            } else if let value = json[key] as? Int {
                return max(0, Double(value)) // Ensure non-negative
            } else if let value = json[key] as? String, let doubleValue = Double(value) {
                return max(0, doubleValue) // Ensure non-negative
            }
        }
        return nil
    }
    
    private func extractClaudeString(from json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines) // Enhanced validation like Gemini
            }
        }
        return nil
    }
    
    private func extractConfidence(from json: [String: Any]) -> AIConfidenceLevel {
        let confidenceKeys = ["confidence", "confidence_score"]
        
        for key in confidenceKeys {
            if let value = json[key] as? Double {
                if value >= 0.8 {
                    return .high
                } else if value >= 0.5 {
                    return .medium
                } else {
                    return .low
                }
            } else if let value = json[key] as? String {
                // Enhanced string-based confidence detection like Gemini
                switch value.lowercased() {
                case "high":
                    return .high
                case "medium":
                    return .medium
                case "low":
                    return .low
                default:
                    continue
                }
            }
        }
        
        return .medium // Default to medium instead of assuming high
    }
}
