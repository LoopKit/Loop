# AutoPresets

Automatically activates a Loop preset when sustained walking or running is detected, and deactivates it when you stop.

## How It Works

AutoPresets uses your iPhone's built-in pedometer and motion classifier (CoreMotion) to detect walking and running. When you start moving, it counts your steps, confirms you're genuinely active, and activates the preset you've assigned to that activity. When you stop, it waits a configurable delay before deactivating.

### Detection Flow

```
Steps accumulate → 20-step threshold reached → Confirmation timer starts
    → Timer fires → Step rate + recency checks → CONFIRMED → Preset activates
        → Walking continues (stop timer resets on each step)
        → Walking stops → Stop delay countdown → DEACTIVATED → Preset removed
```

**Phase 1 — Step Detection:**
The pedometer counts steps continuously. Once 20 steps accumulate, the system advances to Phase 2.

**Phase 2 — Sustained Activity Confirmation:**
A timer runs for the configured Continuous Activity Time (default: 30 seconds). When it fires, three checks must pass:

1. **Step rate:** At least 30 steps/minute over the elapsed window
2. **Recency:** Steps were still changing recently (not walk-then-sit)
3. **Activity type:** CoreMotion's classifier labels the motion as walking or running to select the correct preset

If all checks pass, the assigned preset activates. If any fail, the pedometer resets and detection starts fresh.

**Phase 3 — Stop Detection:**
After confirmation, a stop timer runs for the configured Stop Delay (default: 5 minutes). Every new step restarts this timer. If no steps are detected for the full Stop Delay duration, the preset deactivates and the system resets for the next detection cycle.

### iOS Backgrounding

iOS frequently backgrounds Loop, which delays both pedometer callbacks and timers. A 60-second timer can fire at 200+ seconds. AutoPresets compensates for this:

- Step rate is calculated against **actual** elapsed time, not the configured interval
- The recency limit scales with the timer delay so genuine walks aren't rejected
- The stop timer only restarts when steps actually change (not on every pedometer callback)

## Settings

### Continuous Activity Time
How long sustained activity must continue after the step threshold before the preset activates. Acts as a confirmation window to filter out brief movements like walking to the kitchen.

| Value | Use Case |
|-------|----------|
| 30 sec | Quick activation — good for frequent short walks |
| 1–2 min | Balanced — filters brief movement, catches real walks |
| 5+ min | Conservative — only activates for extended exercise |

**Range:** 10 seconds to 10 minutes

### Stop Delay
How long to wait after you stop moving before deactivating the preset. Prevents the preset from toggling off during brief pauses (stopping at a crosswalk, tying a shoe).

| Value | Use Case |
|-------|----------|
| 1 min | Quick deactivation — preset turns off fast when you stop |
| 3–5 min | Balanced — tolerates short breaks during a walk |
| 10 min | Lenient — keeps preset active through longer pauses |

**Range:** 10 seconds to 10 minutes

### Activity Types
Choose which activities to detect. Each activity type can have a different preset assigned.

- **Walking** — Detected via pedometer + CoreMotion walking classifier
- **Running** — Detected via pedometer + CoreMotion running classifier

### Require High Confidence *(hidden)*
This toggle is hidden in the UI. CoreMotion's activity classifier is too slow and unreliable to gate confirmation — it often doesn't report in time or only reports at medium confidence. The step-based checks (rate + recency) are sufficient for accurate detection. The backend code remains for potential future use.

## Setup

1. **Create a preset in Loop** — Go to Loop Settings and create the override preset you want AutoPresets to activate (e.g., "Walking" with a higher carb ratio target)
2. **Open AutoPresets settings** — Found in Loop Settings
3. **Enable an activity type** — Toggle Walking and/or Running on
4. **Assign a preset** — Select which preset to activate for each enabled activity
5. **Enable AutoPresets** — Toggle the main switch on
6. **Grant Motion permission** — Allow "Motion & Fitness" access when prompted

## Activity Log

The settings screen shows the last 20 events:

- **Preset Activated** — Which preset was activated and for what activity
- **Preset Deactivated** — Includes how long the preset was active
- **Feature Enabled/Disabled** — When AutoPresets was toggled

## Debug Logging

For troubleshooting, enable Debug Logging in the settings to capture detailed detection events:

- Every pedometer update with step counts
- Threshold crossings and timer creation
- Timer fire events with timing analysis
- Confirmation/rejection with specific check results (rate, recency, classifier)
- Stop timer events and deactivation

Logs can be copied to clipboard, viewed in-app, or cleared. They auto-truncate after 5 days or ~100KB.

## Behavior Notes

- **Respects existing overrides:** Won't activate if Loop already has an active override from another source (manual preset, etc.)
- **Only deactivates its own presets:** If you manually activate a different preset while AutoPresets is running, it won't interfere
- **Errors don't disable the feature:** If Motion permission is denied, AutoPresets shows an error but preserves your enabled preference
- **Non-target activity detection:** If CoreMotion detects automotive or cycling at high confidence during an active preset, the stop timer begins
- **Requires at least one preset:** The feature can't be enabled until at least one activity type has a preset assigned

## Architecture

| File | Role |
|------|------|
| `AutoPresetsCoordinator.swift` | Main entry point, coordinates detection and preset activation |
| `ActivityDetectionManager.swift` | CoreMotion pedometer + activity classifier logic |
| `AutoPresetsModels.swift` | Data models, settings, enums, log entries |
| `AutoPresetsStorage.swift` | UserDefaults persistence with legacy migration |
| `AutoPresetsLogger.swift` | File-based debug logging |
| `AutoPresetsSettingsView.swift` | SwiftUI settings UI |

## Permissions

- **Motion & Fitness** — Required. Without it, the pedometer and activity classifier can't run. The feature checks permission status at startup and reports errors if denied.
