# FoodFinder Configuration Guide

This guide walks through every toggle and text field exposed in FoodFinder’s settings so both new users and developers can configure the feature with confidence.

---

## 1. Opening FoodFinder Settings

1. Launch the **Loop** app.
2. Tap the **Settings** tab (gear icon).
3. Scroll to the **FoodFinder** tile under *Services* and tap it.

You’ll land on the FoodFinder summary screen. From here you can:
- **Enable/disable FoodFinder** with a master toggle.
- See quick status for Text Search, Barcode, and AI Analysis.
- Jump into **AI Settings** for detailed configuration.

> **Tip for testers:** The FoodFinder toggle maps to `UserDefaults.standard.foodSearchEnabled` (`foodFinderEnabled` is an alias). It’s safe to enable/disable without losing saved favorites or API keys.

---

## 2. AI Settings Screen Tour

The **AI Settings** sheet hosts the full configuration surface. It is composed of stacked sections. Press **Save** (top-right) when you finish making changes; the view dismisses automatically.

### 2.1 Feature Toggle & Overview

- **Enable FoodFinder** – master switch identical to the summary screen. Disabling hides search UI but keeps all preferences.
- Contextual footers explain that disabling preserves API keys and favorites.

### 2.2 Provider Mapping

FoodFinder can mix and match providers for each search type. The “FoodFinder Provider Configuration” section contains three pickers, each backed by `ConfigurableAIService`:

| Search Type | Options | Notes |
| --- | --- | --- |
| **Text / Voice Search** | OpenFoodFacts (default), USDA FoodData Central, OpenAI, Claude, Gemini, Bring Your Own | AI providers fall back to USDA/OFF when API keys are missing. Use USDA for better brand coverage in the U.S. |
| **Barcode Search** | OpenFoodFacts (default), OpenAI, Claude, Gemini, Bring Your Own | Non-database providers currently fall back to OpenFoodFacts internally; keep OFF as primary for best results. |
| **AI Image Analysis** | OpenAI, Claude, Google Gemini, Bring Your Own, (fallback: Basic Analysis) | Determines which vision model handles food photos. |

Selections persist to `UserDefaults` immediately.

### 2.3 AI Provider Cards

A segmented control switches between bundled providers:

- **OpenAI ChatGPT** – stores API key & optional custom prompt text. Toggle “Use GPT-5 Models” if you have access; otherwise GPT-4o is used.
- **Anthropic Claude** – configure key and optional system prompt.
- **Google Gemini** – configure key and optional custom query instructions.
- **Bring Your Own (BYO)** – supply base URL, key, model/deployment, optional API version, organization, and custom path for OpenAI-compatible endpoints (including Azure OpenAI). A built-in “Test connection” button checks authentication.

Keys are saved into the iOS Keychain. Clear a field to remove the stored value. Show/hide buttons (`eye` icons) toggle secure entry.

### 2.4 USDA API Key (optional)

FoodFinder uses USDA FoodData Central for richer text results. Without a personal key it falls back to the public “DEMO_KEY”, which quickly hits rate limits. The **USDA Database** section links directly to the signup page and stores the key in `UserDefaults.standard.usdaAPIKey`.

### 2.5 Analysis Mode

Choose between:
- **Standard Quality** – highest accuracy (GPT‑4o or GPT‑5 + Gemini 1.5 Pro + Claude Sonnet). Best for mixed meals.
- **Fast Mode** – uses lighter models (GPT‑4o-mini/GPT‑5-nano, Gemini Flash). ~2–3× quicker with a small accuracy trade-off.

Model names for each provider are displayed so developers know which endpoints are hit.

### 2.6 Advanced Options

- **Advanced Dosing Recommendations** – when ON, prompts include extra JSON fields: FPU calculations, fiber impact, exercise notes, absorption timing rationale, safety alerts, and more. The UI exposes these in Carb Entry’s “Advanced Analysis” section. Toggle writes to `UserDefaults.standard.advancedDosingRecommendationsEnabled`.

### 2.7 Save & Cancel

- **Save** – commits all changes (API keys, toggles, custom endpoints) and dismisses the sheet.
- **Cancel** – restores previously persisted values and dismisses without saving.

---

## 3. Standard Behaviour Summary

| Setting | Default | Notes |
| --- | --- | --- |
| Enable FoodFinder | OFF | Keeps existing manual carb entry untouched until you opt in. |
| Text Search Provider | OpenFoodFacts | Switching to USDA improves U.S. branded coverage. |
| Barcode Search Provider | OpenFoodFacts | Other entries currently fall back to OFF. |
| AI Image Provider | Google Gemini | Chosen for speed/cost balance; change as desired. |
| Advanced Dosing | OFF | Turn on once you’re comfortable with FPU-style guidance. |
| GPT‑5 models | OFF | Visible only on the OpenAI tab. Requires paid access. |

---

## 4. FoodFinder Extras

### Favorite Foods Manager
- Accessible from **Settings → Favorite Foods** or directly in Carb Entry after analysis.
- Stores `StoredFavoriteFood` objects locally alongside optional emoji thumbnails.
- Editing honors the same truncation/emoji logic used in Carb Entry.

### Cache & Telemetry
- Image analysis responses are cached for five minutes (see `ImageAnalysisCache`).
- Carb Entry view shows inline telemetry strings during camera analysis for debugging.
- No user-facing switches are required; caches clear automatically.

### Safety & Privacy
- API calls send food descriptions/photos only; Loop never uploads therapy data or identifiers.
- All keys live in Keychain; removing a provider key disables that integration immediately.
- FoodFinder can be disabled any time without losing stored favorites or configurations.

---

## 5. Developer Callouts

- Changes to prompts or response schema belong in `Services/AIFoodAnalysis.swift`; update docs and UI simultaneously.
- Provider bindings live in `ConfigurableAIService`. Adjust defaults there if you need different initial behaviour for forks.
- Keep README screenshots and this guide aligned with Settings UI changes.
- Test flows by running `FoodSearchIntegrationTests` and manual camera/text searches.

FoodFinder’s settings aim to balance power and clarity. 
