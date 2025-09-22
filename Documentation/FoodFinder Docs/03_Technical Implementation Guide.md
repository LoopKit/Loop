# FoodFinder Technical Implementation Guide

This reference is aimed at contributors who want to understand how FoodFinder is wired together inside Loop. It highlights the key modules, control flow, and extension points for adding new functionality.

---

## 1. High-Level Architecture

```
┌──────────────┐        ┌──────────────────┐        ┌──────────────────────┐
│ UI & ViewModels│ ───▶ │   Services       │ ───▶   │ External Providers   │
└──────────────┘        └──────────────────┘        └──────────────────────┘
       │                         │                               │
       ▼                         ▼                               ▼
CarbEntryView         FoodSearchRouter                OpenFoodFacts / USDA
FoodSearchBar         ConfigurableAIService           OpenAI / Claude / Gemini / BYO
FoodFinderSettings    AIFoodAnalysis & Cache          Device Camera / Barcode
AICameraView          OpenFoodFactsService
FavoriteFoods views   BarcodeScannerService
```

- **UI Layer** (SwiftUI) presents search controls, results, advanced analysis, and configuration screens.
- **Services** coordinate data fetching, AI prompt generation, caching, and provider selection.
- **External Providers** include public food databases and user-specified AI services accessed via HTTPS.

---

## 2. Key Modules

### 2.1 UI / ViewModels

| Component | Path | Notes |

| `CarbEntryView` | `Loop/Views/CarbEntryView.swift` | Hosts the search bar, results list, advanced analysis foldout, and favorite food integration. |
| `CarbEntryViewModel` | `Loop/View Models/CarbEntryViewModel.swift` | Owns search text, barcode publisher, AI analysis results, caching of favorites, and absorption time logic. |
| `FoodSearchBar` & `FoodSearchResultsView` | `Loop/Views` | Provide search input plus animated feedback for loading, empty states, and errors. |
| `AddEditFavoriteFoodView` (+ VM) | `Loop/Views` / `View Models` | Handles saving favorites, enforcing truncation, and emoji mapping. |
| `FavoriteFoodsView` | `Loop/Views/FavoriteFoodsView.swift` | Lists stored favorites, supports reordering, editing, and deletion. |
| `FoodFinderSettingsView` | `Loop/Views/FoodFinderSettingsView.swift` | Summary screen with master toggle and quick status. |
| `AISettingsView` | `Loop/Views/AISettingsView.swift` | Full configuration UI for providers, API keys, analysis modes, and advanced features. |
| `AICameraView` | `Loop/Views/AICameraView.swift` | Guides users through capturing food photos, streams telemetry as analysis progresses. |
| `VoiceSearchView` | `Loop/Views/VoiceSearchView.swift` | Optional sheet driven by `VoiceSearchService` (not currently shown in the default UI but available for future use). |

### 2.2 Services & Support Code

| Service | Path | Responsibilities |

| `ConfigurableAIService` | `Loop/Services/AIFoodAnalysis.swift` | Stores provider choices for each search type, exposes API key/query bindings, resolves analysis mode, and pre-encodes images for reuse. |
| `FoodSearchRouter` | `Loop/Services/FoodSearchRouter.swift` | Routes text, barcode, and image requests to the configured provider with fallbacks (e.g., USDA → OpenFoodFacts). |
| `AIFoodAnalysis` | `Loop/Services/AIFoodAnalysis.swift` | Builds prompts, calls providers, parses JSON into `AIFoodAnalysisResult`, and manages caching (`ImageAnalysisCache`). Handles OpenAI, Claude, Gemini, and BYO flows including error translation. |
| `OpenFoodFactsService` | `Loop/Managers/OpenFoodFactsService.swift` | Wraps REST calls to OpenFoodFacts with retry logic and network tuning. |
| `USDAFoodDataService` | `Loop/Services/AIFoodAnalysis.swift` | Text-search helper using USDA FoodData Central when available. |
| `BarcodeScannerService` | `Loop/Services/BarcodeScannerService.swift` | Vision-based barcode detection and deduplication. |
| `VoiceSearchService` | `Loop/Services/VoiceSearchService.swift` | Speech recognition pipeline (authorization, audio capture, error handling). |
| `EmojiThumbnailProvider` & `FavoriteFoodImageStore` | `Loop/Services` | Generate emoji thumbnails and persist them for favorites. |

### 2.3 Data Models

- `OpenFoodFactsProduct` (`Loop/Models/OpenFoodFactsModels.swift`) – parsed database objects with helper properties.
- `AIFoodAnalysisResult` & `FoodItemAnalysis` (`AIFoodAnalysis.swift`) – normalized AI output consumed by UI.
- `SearchProvider` / `SearchType` enums – shared across services and settings.
- `StoredFavoriteFood` (LoopKit) – persisted favorite entries synced with UI.

---

## 3. Data Flow Breakdown

1. **User input** (typing, barcode, camera) updates `CarbEntryViewModel`.
2. View model delegates to `FoodSearchRouter` which chooses the appropriate provider, using cached data if available.
3. When AI analysis is required, `ConfigurableAIService` prepares pre-encoded image data and prompt text via `getAnalysisPrompt()`.
4. `AIFoodAnalysis` issues async network requests using the selected provider client. It automatically falls back (e.g., GPT-5 → GPT-4o) when throttling or errors occur.
5. Responses are parsed into `AIFoodAnalysisResult` where advanced fields are optional unless `advancedDosingRecommendationsEnabled` is true.
6. View model updates published properties; SwiftUI refreshes nutrition circles, advanced sections, favorites, and telemetry.

---

## 4. Advanced Prompt Handling

- `getAnalysisPrompt()` returns `standardAnalysisPrompt + mandatoryNoVagueBlock` and appends `advancedAnalysisRequirements` when advanced dosing is enabled.
- Advanced prompts demand JSON output with additional keys (`fat_protein_units`, `insulin_timing_recommendations`, `absorption_time_hours`, etc.).
- If you add or remove fields, update:
  - Prompt constants in `AIFoodAnalysis.swift`
  - Parsing logic in `parseOpenAIResponse`, `parseClaudeAnalysis`, `parseGeminiAnalysis`
  - UI bindings in `CarbEntryView` and `AICameraView`
  - Documentation 

---

## 5. Caching & Resilience

- **Image cache**: `ImageAnalysisCache` stores AI results keyed by SHA-256 of the pre-encoded image + provider ID for five minutes.
- **Search cache**: `CarbEntryViewModel` caches text search results for five minutes to avoid repeat HTTP calls.
- **Barcode dedupe**: `BarcodeScannerService` throttles identical scans to prevent repeated lookups.
- **Timeout wrapper**: `withTimeoutForAnalysis` guards long-running tasks (default 25–45 seconds based on network quality).

Error enums translate provider responses into localized strings so UI can show actionable messages (missing API key, 429 rate limits, parsing failures, etc.).

---

## 6. Testing & Debugging

- `FoodSearchIntegrationTests` exercise text search, barcode lookups, and selection flows with mocked services (`OpenFoodFactsService.configureMockResponses()`).
- Additional unit tests live under `LoopTests/BarcodeScannerTests.swift` and `LoopTests/OpenFoodFactsTests.swift`.
- `FoodSearchBar` and `AICameraView` print verbose debug logs (`🔍`, `🤖`) to help trace issues while developing. Use Console.app or Xcode’s debug area.
- For manual testing, the **Telemetry** overlay in `AICameraView` displays each stage (image processing, upload, provider selection, etc.).

---

## 7. Extensibility Tips

1. **Adding a new provider**
   - Extend `SearchProvider` and map defaults in `ConfigurableAIService`.
   - Implement provider-specific network code (look at existing `OpenAIFoodAnalysisService` / `ClaudeFoodAnalysisService`).
   - Update prompts if the provider requires different formatting.
   - Wire through `AISettingsView` so users can supply API keys.

2. **Adjusting defaults**
   - Modify `ConfigurableAIService` init to set new default providers or analysis mode.
   - Update docs and release notes for users.

3. **Custom prompt tweaks**
   - Keep the shared `mandatoryNoVagueBlock` aligned across providers.
   - Ensure JSON schema remains backwards compatible with existing UI fields.

4. **Favorites enhancements**
   - `FavoriteFoodsViewModel` trims names and maps emojis. Respect `maxNameLength` constants when surfacing new fields.

---

## 8. Release Checklist

- Run the integration tests and manual camera/text searches with each provider.
- Verify advanced dosing JSON renders correctly when toggled on/off.
- Confirm FoodFinder Settings reflects new options and Save actually persists to `UserDefaults`/Keychain.
- Update this documentation folder and screenshots if the UI changes.

FoodFinder is tightly integrated with Loop’s carb entry workflow. Understanding the few core files above gives you everything you need to extend or debug the system without surprises. Happy hacking!
