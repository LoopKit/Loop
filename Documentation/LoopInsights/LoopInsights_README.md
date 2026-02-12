# LoopInsights — AI-Powered Therapy Settings Analysis

> **Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.**
> Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.

## Overview

LoopInsights is an AI-driven therapy settings advisor for Loop. It analyzes glucose, insulin, and carbohydrate data to suggest adjustments to Carb Ratio (CR), Insulin Sensitivity Factor (ISF), and Basal Rate (BR) schedules that can improve Time in Range.

## Architecture

### Data Flow

```
Loop Core (read-only)
  GlucoseStore ─┐
  DoseStore ────┤── DataAggregator → Aggregated Stats
  CarbStore ────┤                         │
  StoredSettings┘                         ▼
                              AIAnalysis → AI Provider (BYO)
                                          │
                                          ▼
                              Suggestion Cards → User Reviews
                                          │
                              ┌───────────┴────────────┐
                              ▼                        ▼
                    SuggestionStore          User Applies (3 modes)
                    (history log)
```

### File Organization

```
Loop/
├── Models/LoopInsights/
│   ├── LoopInsights_Models.swift           # Core types, enums, data structures
│   └── LoopInsights_SuggestionRecord.swift  # Persistent suggestion log entry
├── View Models/LoopInsights/
│   └── LoopInsights_DashboardViewModel.swift # Main observable, orchestrates analysis
├── Views/LoopInsights/
│   ├── LoopInsights_DashboardView.swift     # Primary entry-point view
│   ├── LoopInsights_SettingsView.swift       # Feature config (AI provider, apply mode)
│   ├── LoopInsights_SuggestionDetailView.swift # Single suggestion detail
│   └── LoopInsights_SuggestionHistoryView.swift # Scrollable suggestion log
├── Services/LoopInsights/
│   ├── LoopInsights_DataAggregator.swift     # Reads stores, computes TIR/stats
│   ├── LoopInsights_AIAnalysis.swift         # Builds prompts, parses responses
│   ├── LoopInsights_AIServiceAdapter.swift   # Provider-agnostic HTTP client
│   ├── LoopInsights_SecureStorage.swift      # Keychain wrapper for API keys
│   └── LoopInsights_SuggestionStore.swift    # UserDefaults persistence for history
├── Resources/LoopInsights/
│   └── LoopInsights_FeatureFlags.swift       # Runtime feature toggles
└── Managers/LoopInsights/
    └── LoopInsights_Coordinator.swift        # Service orchestrator, data bridge

LoopTests/LoopInsights/
├── LoopInsights_ModelsTests.swift            # Model serialization, validation
├── LoopInsights_SuggestionStoreTests.swift   # Store persistence, status transitions
└── LoopInsights_DataAggregatorTests.swift    # Aggregation logic with mock data
```

### Integration Touchpoints

Only **1 existing Loop file** is modified:

| File | Change | Lines |
|------|--------|-------|
| `SettingsView.swift` | NavigationLink to LoopInsights | ~8 |

## Feature Flags

All flags are runtime (`UserDefaults`), not compile-time:

- `LoopInsights_FeatureFlags.isEnabled` — Master on/off (default: off)
- `LoopInsights_FeatureFlags.developerModeEnabled` — Hidden developer mode (default: off)
- `LoopInsights_FeatureFlags.applyMode` — How suggestions are applied (default: manual)
- `LoopInsights_FeatureFlags.analysisPeriod` — Default lookback (default: 14 days)
- `LoopInsights_FeatureFlags.aiConfiguration` — API-agnostic AI endpoint config (default: OpenAI)

### Developer Mode

Activated by long-pressing the LoopInsights header 5 times. Unlocks:
- Auto-Apply mode (suggestions applied automatically for high-confidence)
- Developer section in settings

## Apply Modes

| Mode | Behavior |
|------|----------|
| Manual (default) | Shows values, user navigates to Therapy Settings |
| One-Tap Apply | Writes via SettingsManager with disclaimer confirmation |
| Pre-Fill Editor | Opens editor with proposed value pre-filled |
| Auto-Apply (hidden) | Developer-only, applies high-confidence suggestions |

## AI Provider Support

BYO API key model supporting:
- **OpenAI** (GPT-4o default)
- **Anthropic** (Claude Sonnet 4.5 default)
- **Google** (Gemini 2.0 Flash default)

API key is stored in iOS Keychain and shared with FoodFinder (same Keychain entry).

## Guided Tuning Flow

"One thing at a time" approach:
1. **Carb Ratio** — adjust first (most impact on post-meal variability)
2. **ISF** — adjust second (affects correction doses)
3. **Basal Rate** — adjust last (affects entire 24-hour profile)

## Safety

- Suggestions are capped at 20% change from current values
- Conservative approach: under-adjust > over-adjust
- All changes logged in suggestion history with before/after snapshots
- User always sees disclaimer when applying changes
- Feature flag defaults to OFF

## Portability

- All code in `LoopInsights/` subdirectories with `LoopInsights_` prefix
- No LoopKit modifications — Loop target only
- Runtime feature flags (not compile-time)
- Data access through existing LoopKit protocols
- Merge script viable: copy subdirectories + apply SettingsView patch + run pbxproj script
