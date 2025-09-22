# FoodFinder Troubleshooting Guide

Use this checklist when FoodFinder behaves unexpectedly. Each section pairs symptoms with practical fixes so support volunteers, clinicians, and users can work through problems quickly.

---

## 1. Feature Availability

### FoodFinder controls do not appear in Carb Entry
- **Verify the toggle**: Settings → FoodFinder → **Enable FoodFinder** must be ON.
- **App version**: FoodFinder ships with Loop 3.x builds in this repo. Older Loop releases won’t expose the UI.
- **iOS permissions**: If the barcode or camera buttons are missing, check **Settings → Privacy → Camera → Loop**.
- **Developer tip**: ensure `UserDefaults.standard.foodSearchEnabled` is true when loading `CarbEntryView` in previews/tests.

### API analysis never runs
- Confirm **AI Settings → Enable FoodFinder** and **AI analysis provider** have valid API keys.
- The search bar still works without AI, but advanced insights and photo analysis require keys.
- After entering a key, tap **Save** before closing the sheet.

---

## 2. API & Connectivity

### “Missing API key”, “Authentication failed”, or 401/403 errors
- Re-enter the API key and double-check copied characters (OpenAI keys start with `sk-`, Claude with `sk-ant-`).
- Make sure the key has access to the correct model (GPT‑4o/GPT‑5, Claude 3 Haiku, Gemini 1.5 Flash).
- If you rotated a key on the provider dashboard, remove the old one from AI Settings first so Loop stops using it.

### Frequent 429 / quota exceeded messages
- View usage on the provider dashboard; add billing or raise limits if desired.
- Use favorites to avoid re-analysing the same meal repeatedly.
- Switch temporarily to a different provider (e.g., Gemini when OpenAI is at quota).
- For text search, add your own USDA key to avoid the public DEMO_KEY throttle.

### “Network unavailable” or request timeout
- Test another network-dependent app to confirm connectivity.
- Toggle airplane mode or switch between Wi‑Fi and cellular.
- Providers occasionally have outages—check their status pages (OpenAI, Anthropic, Google Cloud).

---

## 3. Search & Result Quality

### No results returned for text search
- Try more specific terms (“grilled chicken thigh” rather than “chicken”).
- For brand items, include the brand name or scan the barcode.
- Ensure internet access; text search queries OpenFoodFacts and optional USDA endpoints.

### Nutrition values look wrong
- Confirm the serving multiplier matches your portion; adjust manually if needed.
- Restaurant meals vary widely—use AI’s notes as guidance, not absolute truth.
- Cross-check with packaging or trusted nutrition references for critical decisions.

### Advanced analysis section missing
- Enable **Advanced Dosing Recommendations** in AI Settings and ensure AI analysis succeeded.
- Simple foods (plain water, unlabelled sugar) may not generate extra content; complex meals are more likely to show FPUs and timing guidance.

---

## 4. Barcode & Camera

### Barcode won’t scan
- Verify camera permission (Settings → Privacy → Camera → Loop).
- Hold the device steady 6–8 inches away with good lighting. Clean the lens if needed.
- Some niche barcodes are unsupported—switch to text search or manual entry in those cases.

### “Product not found” after scanning
- OpenFoodFacts may not have the item yet. Try typing the product name or entering values from the label.
- Users can contribute missing items at [openfoodfacts.org](https://openfoodfacts.org) to improve future coverage.

### Photo analysis fails or is very inaccurate
- Retake the photo: frame the entire plate, remove clutter, and add scale references (fork, 10" plate).
- Ensure your chosen provider supports vision (OpenAI GPT‑4o/5, Gemini 1.5 Flash, Claude Haiku). If in doubt, switch providers.
- You can edit or replace AI results manually before saving.

---

## 5. Favorites & Data Management

### Favorite names truncated or missing icons
- Names are limited to 30 characters; edit the favorite in **Settings → Favorite Foods** to shorten it.
- FoodFinder auto-applies emoji icons for simple items (apple, banana). Non-mapped foods stick with text only—this is expected.

### Favorites disappear
- Favorites live in device storage. Restoring from an old backup or reinstalling Loop with a clean slate resets them.
- Verify **Settings → Favorite Foods** rather than relying solely on the Carb Entry shortcut list.

### Clearing data
- Disabling FoodFinder leaves favorites intact; delete them manually if you want a clean slate.
- Cached AI responses expire automatically after five minutes—no manual action required.

---

## 6. When to Seek Additional Help

- **Medical questions**: Share AI outputs with your diabetes care team before adjusting therapy.
- **Persistent technical issues**: Capture logs from Xcode/Console for developers or file an issue with reproduction steps.
- **Provider billing problems**: Contact the AI provider directly (OpenAI, Anthropic, Google). Loop does not manage those accounts or providers.

FoodFinder is designed to fail safely—if AI is unavailable, manual carb entry remains untouched. Use this guide to get back on track quickly and report any bugs you can reproduce so we can keep improving the experience.
