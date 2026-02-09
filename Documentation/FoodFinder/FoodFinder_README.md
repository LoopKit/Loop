# FoodFinder for Loop

FoodFinder adds AI-powered food identification and nutrition lookup to Loop's carb entry workflow. It supports barcode scanning (via OpenFoodFacts), AI camera analysis, voice search, and text-based food search — all integrated with a minimal footprint into Loop's existing codebase.

## Features

- **Barcode Scanner** — Scan product barcodes to look up nutrition data from OpenFoodFacts
- **AI Camera Analysis** — Take a photo of food and get AI-powered carb estimates (supports Claude, OpenAI, Google Gemini, and custom BYO providers)
- **Voice Search** — Speak a food name to search for nutrition information
- **Text Search** — Type a food name for quick lookup
- **Favorite Food Thumbnails** — Saved favorites display thumbnail images for easy identification
- **Configurable AI Providers** — Choose between multiple AI backends or bring your own API endpoint

## Architecture

FoodFinder follows the **minimal footprint principle**: all feature logic lives in dedicated `FoodFinder/` subdirectories, with fewer than 30 lines added to existing Loop files.

### Directory Structure

```
Loop/Loop/
├── Views/FoodFinder/           (11 files — all UI components)
├── Models/FoodFinder/          (3 files — data models)
├── Services/FoodFinder/        (13 files — API clients, scanning, AI)
├── View Models/FoodFinder/     (2 files — state management)
├── Resources/FoodFinder/       (1 file — feature flags + settings keys)
└── Documentation/FoodFinder/   (this file)

Loop/LoopTests/FoodFinder/      (3 files — unit tests)
```

### Integration Touchpoints

Only 3 existing Loop files are modified, totaling ~29 lines:

| File | Lines Added | Purpose |
|------|-------------|---------|
| `CarbEntryView.swift` | ~9 | Inserts `FoodFinder_EntryPoint` view |
| `SettingsView.swift` | ~16 | Adds FoodFinder Settings navigation link |
| `FavoriteFoodDetailView.swift` | ~4 | Adds thumbnail display for favorites |

### Key Files

| File | Role |
|------|------|
| `FoodFinder_FeatureFlags.swift` | Central on/off toggle and all UserDefaults keys |
| `FoodFinder_EntryPoint.swift` | Self-contained carb entry UI (search, scan, results) |
| `FoodFinder_SearchViewModel.swift` | All search/scan/AI state management |
| `FoodFinder_SettingsView.swift` | AI provider configuration screen |

## Enabling/Disabling

FoodFinder is controlled by a single toggle in `FoodFinder_FeatureFlags.swift`:

```swift
FoodFinder_FeatureFlags.isEnabled  // returns Bool
```

When disabled, all FoodFinder UI is hidden and no FoodFinder code executes. The feature can be toggled via the `foodSearchEnabled` UserDefaults key.

## AI Provider Configuration

FoodFinder supports multiple AI providers for food photo analysis:

1. **Claude** (Anthropic) — Requires API key
2. **OpenAI** (GPT-4 Vision) — Requires API key
3. **Google Gemini** — Requires API key
4. **BYO (Bring Your Own)** — Custom endpoint URL + API key

Providers are configured in Settings > FoodFinder Settings. API keys are stored in UserDefaults with `foodFinder_` prefixed keys.

## Portability

FoodFinder is designed for easy adoption into other Loop forks (Trio, IAPS, Tidepool Loop):

- **No LoopKit submodule changes** — All code lives under the Loop/ submodule
- **Self-contained feature flag** — Single file controls enable/disable
- **Prefixed naming** — All files use `FoodFinder_` prefix to avoid naming conflicts
- **Minimal touchpoints** — Only 3 files need small modifications in the host app
- **Script-installable** — The `FoodFinder/` directories can be copied and the 3 touchpoints applied programmatically

## Dependencies

FoodFinder uses only Apple frameworks available on iOS:

- `Vision` — Barcode detection
- `AVFoundation` — Camera access for scanning and AI analysis
- `Speech` — Voice search recognition
- `SwiftUI` / `UIKit` — User interface

No third-party dependencies are required.

## Testing

Unit tests are located in `LoopTests/FoodFinder/`:

- `FoodFinder_OpenFoodFactsTests.swift` — API response parsing tests
- `FoodFinder_BarcodeScannerTests.swift` — Barcode detection tests
- `FoodFinder_VoiceSearchTests.swift` — Voice recognition tests
