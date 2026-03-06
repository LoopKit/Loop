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

## Data Sharing (DataLayer)

LoopInsights includes an optional **DataLayer** module that can collect and share anonymized health data for research and provider sharing. **On first launch, data collection is enabled by default** with all categories (glucose, insulin, carbs, biometrics, AI behavioral, substances, activity) opted in.

**No data is uploaded unless an ingest endpoint is configured.** The open-source default has no endpoint set, so data stays on-device only. If you or your fork configures an ingest endpoint, data will be transmitted.

**To review or disable data sharing:**

1. Open **Settings > LoopInsights**
2. Tap **Data Sharing**
3. Turn off the **Enable Data Sharing** master toggle to disable all collection, OR
4. Toggle individual categories on/off for granular control
5. Turn off **Contribute to Research** to stop research uploads while keeping provider sharing

All data is stored locally with a 90-day retention policy and can be deleted at any time from the Data Sharing screen.

## Safety

- Suggestions are capped at 20% change from current values
- Conservative approach: under-adjust > over-adjust
- All changes logged in suggestion history with before/after snapshots
- User always sees disclaimer when applying changes
- Feature flag defaults to OFF

## Test Data

LoopInsights includes a **Test Data mode** (developer-only) that loads JSON fixture files instead of reading from Loop's live data stores. This is useful for development, demos, and for users who want to evaluate the feature without waiting for real data accumulation.

### How Test Data Works

`LoopInsights_TestDataProvider` looks for fixture files in two locations (checked in order):

1. **App Documents** — `Documents/LoopInsights/` on the device (no rebuild needed)
2. **App Bundle** — `Resources/LoopInsights/TestData/` (requires rebuild)

Expected fixture filenames:
- `tidepool_glucose_samples.json` — CGM glucose readings (`StoredGlucoseSample` format)
- `tidepool_dose_entries.json` — Insulin deliveries (`DoseEntry` format)
- `tidepool_carb_entries.json` — Carb entries (`StoredCarbEntry` format)
- `tidepool_therapy_settings.json` — Therapy settings (optional, custom format)

### Enabling Test Data Mode

1. Open **Settings > LoopInsights**
2. Long-press the LoopInsights header **3 times** to unlock Developer Mode
3. Scroll to the Developer section
4. Toggle **"Use Test Data Fixtures"** on
5. Open the Dashboard and run an analysis

### Generating Test Data from Tidepool

A Python script (`pull_tidepool_data.py`) is included to pull real diabetes data from a Tidepool account and convert it into the fixture format LoopInsights expects.

**Prerequisites:**
```bash
pip3 install requests
```

**Usage:**
```bash
# Pull 14 days of data (default)
python3 pull_tidepool_data.py --email **YOUR_TIDEPOOL_EMAIL** --password **YOUR_TIDEPOOL_PASSWORD**

# Pull 90 days for longer-range analysis testing
python3 pull_tidepool_data.py --email **YOUR_EMAIL** --password **YOUR_PASSWORD** --days 90

# Pull data and auto-copy to the iOS Simulator's Documents/LoopInsights/
python3 pull_tidepool_data.py --email **YOUR_EMAIL** --password **YOUR_PASSWORD** --simulator

# Specify a custom output directory
python3 pull_tidepool_data.py --email **YOUR_EMAIL** --password **YOUR_PASSWORD** --output /path/to/output
```

**What the script does:**
1. Authenticates with the Tidepool API (`api.tidepool.org`)
2. Pulls CGM glucose (cbg), insulin doses (basal + bolus), carb entries (wizard + food), and pump settings
3. Converts Tidepool's data format to Loop's native JSON format
4. Saves four fixture files to `LoopWorkspace/Loop/Loop/Resources/LoopInsights/TestData/`
5. With `--simulator`, copies the fixtures into the most recent iOS Simulator's `Documents/LoopInsights/` directory

**After running the script:**
1. Build and run Loop in the Simulator (or on-device if you placed files in the app's Documents)
2. Enable LoopInsights in Settings
3. Unlock Developer Mode (5x long-press on header)
4. Enable "Use Test Data Fixtures"
5. Open the Dashboard and tap Analyze

### Creating Test Data Manually

If you don't have a Tidepool account, you can create fixture files manually. Each file is a JSON array.

**Glucose samples** (`tidepool_glucose_samples.json`):
```json
[
  {
    "startDate": "2026-02-01T08:00:00Z",
    "quantity": 120.0,
    "provenanceIdentifier": "com.test",
    "syncIdentifier": "sample-001",
    "syncVersion": 1,
    "isDisplayOnly": false,
    "wasUserEntered": false
  }
]
```

**Dose entries** (`tidepool_dose_entries.json`):
```json
[
  {
    "type": "tempBasal",
    "startDate": "2026-02-01T08:00:00Z",
    "endDate": "2026-02-01T08:30:00Z",
    "value": 0.85,
    "unit": "U/hour",
    "automatic": true
  },
  {
    "type": "bolus",
    "startDate": "2026-02-01T12:00:00Z",
    "endDate": "2026-02-01T12:01:00Z",
    "value": 3.5,
    "unit": "U",
    "isMutable": false
  }
]
```

**Carb entries** (`tidepool_carb_entries.json`):
```json
[
  {
    "startDate": "2026-02-01T12:00:00Z",
    "quantity": 45,
    "absorptionTime": 10800,
    "syncIdentifier": "carb-001",
    "syncVersion": 1,
    "createdByCurrentApp": false
  }
]
```

**Therapy settings** (`tidepool_therapy_settings.json`, optional):
```json
{
  "basalRateSchedule": [
    {"startTime": 0, "value": 0.8},
    {"startTime": 21600, "value": 0.9},
    {"startTime": 43200, "value": 0.75}
  ],
  "insulinSensitivitySchedule": [
    {"startTime": 0, "value": 45},
    {"startTime": 21600, "value": 40},
    {"startTime": 43200, "value": 50}
  ],
  "carbRatioSchedule": [
    {"startTime": 0, "value": 10},
    {"startTime": 21600, "value": 8},
    {"startTime": 43200, "value": 12}
  ]
}
```

> **Note:** `startTime` values are in seconds from midnight (e.g., 21600 = 6:00 AM, 43200 = 12:00 PM).

### Loading Fixtures on a Physical Device

To load test data on a physical device without rebuilding:

1. Connect the device to your Mac
2. Open Finder > select the device > Files tab
3. Drag-and-drop the four JSON files into the **Loop** app's Documents folder, inside a `LoopInsights` subfolder
4. Enable Test Data mode in LoopInsights Developer settings

The `TestDataProvider` checks `Documents/LoopInsights/` first, so user-provided files always take priority over bundled fixtures.

## Portability

- All code in `LoopInsights/` subdirectories with `LoopInsights_` prefix
- No LoopKit modifications — Loop target only
- Runtime feature flags (not compile-time)
- Data access through existing LoopKit protocols
- Merge script viable: copy subdirectories + apply SettingsView patch + run pbxproj script
