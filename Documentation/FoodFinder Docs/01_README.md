# FoodFinder Documentation Hub

FoodFinder brings AI-assisted carb discovery, nutritional lookups, and diabetes-oriented analysis to Loop. This folder gathers everything you need—from wiring the feature into code to helping someone use it safely in day-to-day therapy.

## How To Use These Docs

| Audience | Start Here | Why |
| --- | --- | --- |
| Curious user / caregiver | [04_End User Guide] | Walks through enabling FoodFinder, running searches, and interpreting AI results. |
| Power user configuring providers | [02_Configuration and Settings] | Explains every toggle, provider option, and when to use each choice. |
| Developers & contributors | [03_Technical Implementation Guide] | Details the architecture, key classes, and test touch points. |
| Support / troubleshooting | [05_Troubleshooting Guide] | Symptoms → causes → fixes for the most common questions. |

## Quick Facts

- **Feature name**: FoodFinder (settings alias `foodFinderEnabled` → `foodSearchEnabled`)
- **Entry points**: Carb Entry screen search bar (text + barcode + AI camera) and the FoodFinder Settings card
- **AI providers**: OpenAI, Anthropic Claude, Google Gemini, or a custom (BYO) OpenAI-compatible endpoint
- **Local data**: Favorites, cached analysis, and settings all live on-device; nothing is sent to Loop servers
- **Advanced dosing**: Optional, off by default; adds FPU, fiber adjustments, exercise notes, timing guidance, and safety alerts

## For Developers in a Hurry

1. Skim the [Technical Implementation Guide] to see how `CarbEntryView`, `FoodSearchRouter`, `ConfigurableAIService`, and `AIFoodAnalysis` fit together.
2. Review `LoopWorkspace/Loop/Loop/View Models/CarbEntryViewModel.swift` for state flows (search text, barcode streaming, AI results, favorites).
3. Tests live under `LoopWorkspace/Loop/LoopTests/FoodSearchIntegrationTests.swift` with helper mocks in `LoopKitUI`.
4. Provider prompts & caching logic live in `Services/AIFoodAnalysis.swift`—if you change output fields, update the docs and UI.

## For Support & Educators

- Point new users to the [End User Guide](04_End%20User%20Guide.md).
- Use the [Configuration](02_Configuration%20and%20Settings.md) doc when helping someone wire API keys or USDA access.
- Reference the [Troubleshooting Guide](05_Troubleshooting%20Guide.md) for copy/paste ready answers about API failures, long-running analyses, or missing advanced sections.

Happy searching! If you spot mismatches between docs and UI, file an issue or PR so everything stays in sync.
