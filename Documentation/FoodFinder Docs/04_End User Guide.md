# FoodFinder End User Guide

FoodFinder adds quick food lookups, barcode scanning, and AI-powered photo analysis to Loop. This guide explains how to turn it on, connect AI providers, and make sense of the results—whether you are a person living with diabetes, a caregiver, or a clinician helping someone set it up.

---

## 1. Enable FoodFinder

1. Open the **Loop** app and tap **Settings** (gear icon).
2. Choose **FoodFinder** from the list.
3. Toggle **Enable FoodFinder** to ON.

Food controls now appear inside the carb entry screen: a search bar, barcode button, and AI camera button.

> **Note:** Disabling FoodFinder later hides the UI but keeps favorites, API keys, and preferences intact.

---

## 2. Connect an AI Provider (optional but recommended)

AI analysis unlocks detailed nutrition breakdowns, dynamic absorption times, and advanced diabetes guidance. You can use FoodFinder with or without AI:

1. From the FoodFinder summary screen tap **AI Settings**.
2. In the **AI API KEY CONFIGURATION** section choose a provider:
   - **OpenAI (GPT‑4o/GPT‑5)** – highest accuracy and best vision model. Typical cost ≈ $0.007–$0.015 per food photo.
   - **Anthropic Claude 3 Haiku** – fast text reasoning; cost ≈ $0.004 per analysis.
   - **Google Gemini 1.5 Flash** – most affordable, ≈ $0.001–$0.003 per analysis.
   - **Bring Your Own (BYO)** – custom OpenAI-compatible endpoint or Azure deployment.
3. Paste in your API key and tap **Save**. Keys are stored securely in the iOS Keychain.
4. Optional: Add a **USDA FoodData Central** API key for more reliable text searches (the public DEMO_KEY frequently hits rate limits).

You can switch providers at any time. If a key is missing, FoodFinder falls back to free database results automatically.

---

## 3. Using FoodFinder in Carb Entry

### 3.1 Text Search
- Tap **Add Carb Entry**.
- Start typing a food (e.g., “grilled salmon with rice”). Suggestions update automatically.
- Select the result that best matches your meal. FoodFinder analyzes the nutrition and shows the summary instantly.

### 3.2 Barcode Scan
- Tap the **barcode icon** next to the search bar.
- Point your camera at a package barcode. When it vibrates, the product is identified.
- FoodFinder retrieves nutrition facts from OpenFoodFacts and, if AI analysis is enabled, refines the data for portion size and diabetes guidance.

### 3.3 AI Camera Analysis
- Tap the **sparkles/camera icon**.
- Take a clear photo of your meal (good lighting, full plate visible).
- FoodFinder uploads the image to the selected AI provider, then displays:
  - Recognized foods and portion estimates
  - Nutrition totals (carbs, protein, fat, fiber, calories)
  - Confidence score and notes
  - Optional advanced dosing guidance (see below)

Photos are not stored on any servers; they stay local unless you save them elsewhere.

### 3.4 Favorites
- After FoodFinder analyzes a meal, tap **Save** on the “New Favorite Food” sheet.
- Give it a short name (30 characters max). If the food matches a known item, FoodFinder automatically stores an emoji icon.
- Favorites appear at the top of the carb entry screen for one-tap reuse.
- Manage favorites under **Settings → Favorite Foods** (edit, reorder, delete).

---

## 4. Understanding the Results Screen

1. **Nutrition Summary** – Rings at the top show carbs, calories, fat, fiber, and protein for the selected portion. Adjust servings and the numbers recalculate immediately.
2. **Food Details** – Expand the list to see each component (e.g., chicken, rice, broccoli) with its own portion estimate and macronutrients.
3. **Diabetes Considerations** – Plain-language notes about glycemic index, absorption patterns, or recommended monitoring.
4. **Advanced Analysis** (optional) – Appears when **Advanced Dosing Recommendations** is enabled in settings. Sections may include:
   - **Fat/Protein Units (FPUs)** with suggested extended bolus percentages.
   - **Net Carb Adjustments** that account for significant fiber.
   - **Insulin Timing Guidance** tailored to simple vs. complex meals.
   - **Exercise Considerations** for pre/post workout meals.
   - **Absorption Time** suggestions with reasoning (e.g., “5.5 h due to high fat + fiber”).
   - **Safety Alerts** highlighting potential hypo/hyper risks.

Always review AI suggestions and adjust based on your own experience or provider guidance.

---

## 5. Keeping Costs Manageable

- **Favorites** – reuse frequent meals without triggering new AI charges.
- **Text & Barcode** – database lookups are free; AI is only invoked when needed.
- **Provider choice** – Gemini is the most economical, OpenAI the most precise; switch depending on your current needs.
- **Check usage** – each provider offers a dashboard where you can view monthly spend and set caps.

If an analysis fails due to quota or rate limits, FoodFinder shows an error and falls back to simpler data when possible.

---

## 6. Privacy & Safety

- Food descriptions, images, and barcodes are sent directly to the provider you configure. Loop never shares glucose data, therapy settings, or personal identifiers.
- API keys stay on your device. Removing a key immediately stops further requests.
- FoodFinder is an **assistive tool**. Always double-check nutrition estimates, monitor your glucose, and follow advice from your healthcare team.

---

## 7. Troubleshooting Checklist

| Issue | Quick Fix |
| --- | --- |
| FoodFinder controls missing | Ensure **Enable FoodFinder** is ON in settings. |
| AI says “Missing API key” | Re-enter the key in AI Settings and tap Save, then retry. |
| Frequent “429 / rate limit” errors | Add a personal USDA key for text search or switch to a different AI provider temporarily. |
| Photo analysis inaccurate | Retake with better lighting and include common scale references (fork, plate). |
| Advanced section not visible | Turn on **Advanced Dosing Recommendations** and make sure AI Analysis is enabled. |

See the [Troubleshooting Guide] for deeper step-by-step advice.

---

## 8. Best Practices

- Describe foods precisely (“grilled skinless chicken breast, 6 oz” beats “chicken”).
- Review AI output and tweak servings when it clearly over/underestimates.
- Start conservatively with new dosing suggestions and consult your care team for adjustments.
- Keep Loop and iOS up to date—provider SDK improvements often depend on the latest system releases.

FoodFinder should feel like a helper, not a hurdle. If something looks off, fall back to familiar carb counting and report the issue so the community can improve it.
