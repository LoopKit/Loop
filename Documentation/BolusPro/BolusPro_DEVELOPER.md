# BolusPro — Developer Guide

## Architecture

BolusPro is a feature-flagged, opt-in module that adds a per-meal toggle + slider to Loop's `CarbEntryView`. When enabled, it produces **two paired `NewCarbEntry` records** on submit instead of one — a primary carb entry (user's actual carbs) and a secondary "FPU tail" entry timed for the delayed protein/fat glucose effect.

It deliberately avoids LoopKit changes — the dual-entry model uses two ordinary `NewCarbEntry` writes via the existing `BolusEntryViewModelDelegate.addCarbEntry()` path. The only LoopKit data it touches is `NewCarbEntry`'s `foodType` field, which carries 🥩 on the secondary entry as a visual marker.

## File map

```
Loop/
├── Models/BolusPro/
│   └── BolusPro_Models.swift          // BolusProEntryState, BolusProMacroInputs,
│                                      //   BolusProFPUResult value types
├── Resources/BolusPro/
│   └── BolusPro_FeatureFlags.swift    // Master toggle, tunables, UserDefaults keys
├── Services/BolusPro/
│   ├── BolusPro_FPUCalculator.swift   // Stateless math + secondary entry generator
│   ├── BolusPro_DataLayerHook.swift   // Per-meal analytics snapshot + post hook
│   └── BolusPro_BehaviorAnalyzer.swift // Singleton observer, snapshot store, pattern producer
├── Views/BolusPro/
│   ├── BolusPro_InfoSheet.swift       // (i) explainer presented from anywhere
│   ├── BolusPro_OnboardingView.swift  // First-run intro
│   ├── BolusPro_ManualMacroFields.swift // Fat & protein inputs (no-AI path)
│   ├── BolusPro_CarbEntrySection.swift  // Toggle + slider, embedded in CarbEntryView
│   └── BolusPro_SettingsView.swift    // Settings subpage

Documentation/BolusPro/
├── BolusPro_README.md      // User guide
└── BolusPro_DEVELOPER.md   // This file
```

## Existing Loop files modified (minimal-impact wiring)

| File | Diff size | Why |
|---|---|---|
| `Loop/Views/CarbEntryView.swift` | +6 lines | Embeds `BolusPro_CarbEntrySection` below absorption time row; adds `onMacrosResolved` callback to FoodFinder_EntryPoint |
| `Loop/Views/SettingsView.swift` | +14 lines | Adds `bolusProSettingsRow` between AutoPresets and FoodFinder (alphabetical) |
| `Loop/View Models/CarbEntryViewModel.swift` | +44 lines | Adds `bolusProState`, `applyBolusProMacrosFromFoodFinder`, secondary-entry construction in `setBolusViewModel` |
| `Loop/View Models/BolusEntryViewModel.swift` | +14 lines | Adds `bolusProSecondaryEntry` + `bolusProAnalyticsSnapshot` properties; saves secondary entry and fires DataLayer hook in `saveAndDeliver` |
| `Loop/View Models/FoodFinder/FoodFinder_SearchViewModel.swift` | +30 lines | Adds `fat`, `protein`, `macrosSource` to `FoodFinder_NutritionResult`; populates from 4 call sites (AI re-applied, product selection, favorite food, AI item-deletion) |
| `Loop/Views/FoodFinder/FoodFinder_EntryPoint.swift` | +7 lines | Adds optional `onMacrosResolved` callback that forwards macros from `searchVM.onNutritionApplied` to host |
| `Loop/Models/DataLayer/DataLayer_EventModels.swift` | +35 lines | Adds `bolusProEntry` event type + `DataLayer_BolusProPayload` struct (12 fields) |
| `Loop/Managers/DataLayer/DataLayer_Coordinator.swift` | +5 lines | Calls `BolusPro_FeatureFlags.registerDefaults()` and `BolusPro_BehaviorAnalyzer.shared.start()` at app launch |
| `Loop/Views/LoopInsights/LoopInsights_BehaviorInsightsView.swift` | +45 lines | Loads BolusPro patterns alongside FoodFinder correction patterns; renders new "BolusPro Patterns" section |

Total: ~200 lines across 9 existing Loop files. No LoopKit changes.

## Data flow at submit

```
User taps Continue in CarbEntryView
  └─→ CarbEntryViewModel.continueToBolus()
       └─→ setBolusViewModel()
            ├── Builds primary NewCarbEntry (existing behavior)
            ├── Builds secondary NewCarbEntry via BolusPro_FPUCalculator (if enabled)
            ├── Builds BolusProAnalyticsSnapshot (always, when master flag on)
            ├── Attaches both to BolusEntryViewModel
            └── Pushes to BolusEntryView

User taps Deliver Bolus in BolusEntryView
  └─→ BolusEntryViewModel.saveAndDeliver()
       ├── saveCarbEntry(primary) via delegate
       ├── saveCarbEntry(secondary) via delegate (if attached)
       └── BolusPro_DataLayerHook.recordSavedEntry(snapshot)
            ├── DataLayer_EventCollector.shared.record(.bolusProEntry, payload)
            └── NotificationCenter.post(.bolusProEntrySaved)
                 └─→ BolusPro_BehaviorAnalyzer.shared appends to local store
```

## Secondary-entry math

The secondary entry's grams come from Trio's modified-Pankowska formula:

```
bonus_grams = (fat × 0.9 + protein × 0.4) × coverage_factor × slider_position
```

- `coverage_factor` is a per-user setting (default 0.50, range 0.10–1.00)
- `slider_position` is the per-meal slider (0.0–1.0, default 1.0)
- Final value is rounded to 1 decimal place
- The entry is only written if `bonus_grams >= 1.0` (anything less is noise)

Timing:
- `startDate` = primary `startDate` + `fpuDelayMinutes` (default 60)
- `absorptionTime` = `fpuAbsorptionHours` (default 6)
- `foodType` = "🥩"

## FPU score (display-only)

```
fpu_score = (fat × 9 + protein × 4) / 100
```

This is the strict Warsaw definition (1 FPU = 100 kcal). Used for the on-screen "X.X FPU" pill and the auto-detect threshold check. **Not used for dosing math.** Dosing uses the gram formula above.

## Auto-detection

When `BolusPro_FeatureFlags.autoDetectFromFoodFinder` is on, FoodFinder-supplied macros are run through `BolusPro_FPUCalculator.calculate(...)`. If `crossesAutoTriggerThreshold` (i.e. `fpu_score >= triggerThresholdFPU`, default 1.5), the per-entry toggle flips on automatically and `bolusProState.autoDetected = true`.

## DataLayer event

`DataLayer_BolusProPayload` carries 12 fields per meal save:

```swift
enabled                  // Bool — toggle state at submit
autoDetected             // Bool? — was auto-flipped (nil when toggle off)
macrosSource             // String? — "ai" | "product" | "favorite" | "manual"
fpuScore                 // Double — Warsaw kcal-based score
bonusGrams               // Double — secondary entry size
sliderPosition           // Double? — 0.0–1.0 (nil when toggle off)
coverageFactorPercent    // Int — 10–100
fpuDelayMinutes          // Int — 0–120
fpuAbsorptionHours       // Int — 4–8
fatGramsInput            // Double — raw fat that drove calc
proteinGramsInput        // Double — raw protein that drove calc
primaryCarbGrams         // Double — primary entry size (for ratio analysis)
```

Event fires on **every** meal save when the master flag is on, **regardless of whether the per-entry toggle was on or off**. This captures non-adoption signal alongside adoption.

## BehaviorInsights patterns

`BolusPro_BehaviorAnalyzer.shared.analyzePatterns()` returns up to 5 `BolusProBehaviorPattern` rows over a 30-day window:

| Kind | Surfaced as |
|---|---|
| `adoption` | "BolusPro used on X% of meals" |
| `sliderDrift` | "Your typical slider sits at X%" |
| `autoDetectOverride` | "Kept BolusPro on for X% of high-FPU meals" |
| `bonusDistribution` | "Average BolusPro bonus is Xg" |
| `macrosSourceMix` | "Macros come from {AI / barcode / favorite / manual} most often" |

Min meal count for any pattern: 3. Window: last 30 days.

## pbxproj patch

`Scripts/add_bolus_pro_files.py` is a one-shot script that adds all 10 new files to `Loop.xcodeproj/project.pbxproj`. Uses `FoodFinder_FeatureFlags.swift` as anchor and rewrites the FileRef path to escape the FoodFinder group via `../../<relpath>`.

**Caveat:** New files appear under the FoodFinder group in Xcode's navigator, not in proper BolusPro/ subgroups. The build is unaffected. A follow-up cleanup PR can move them into BolusPro/ subgroups if desired.

## Installer support

When deploying to `feat/installer`:
- Add all 10 BolusPro files to `Scripts/install_features.sh` `NEW_FILES` array
- Add all 10 to `Scripts/update_pbxproj.py` `SOURCE_FILES` array
- Add Settings template insert for `bolusProSettingsRow` to `install_features.sh` `FEATURE_ROWS`

Without these, Option B installs will silently miss BolusPro files (per the AlcoholTracker postmortem).

## Known limitations / V2 backlog

- **No "cancel tail" action.** If user goes low after BolusPro meal, they have to manually edit/delete the 🥩 entry. V2: one-tap cancel on active-carbs row.
- **No per-food-category learning.** Slider drift is global. V2: track per-foodType and pre-position slider based on history.
- **No outcome correlation in v1.** BolusPro snapshots are emitted, but the Meal Debrief loop doesn't yet correlate them with post-meal CGM trace. V2: add `BolusProMeal` to MealDebrief comparison set.
- **Files in FoodFinder Xcode group** (functional but visually misleading; can be regrouped manually).
