# SiteAtlas — Developer Documentation

## Architecture Overview

SiteAtlas follows the same architectural pattern as AutoPresets and FoodFinder:

```
Coordinator (singleton) → Storage (JSON) → Views (SwiftUI)
```

### Components

| Layer | File | Purpose |
|-------|------|---------|
| Feature Flag | `Services/SiteAtlas/SiteAtlas_FeatureFlags.swift` | On/off toggle via UserDefaults |
| Models | `Models/SiteAtlas/SiteAtlas_Models.swift` | Data types, theme colors, age-based color scale |
| Storage | `Services/SiteAtlas/SiteAtlas_Storage.swift` | JSON persistence, pruning, update support |
| Coordinator | `Services/SiteAtlas/SiteAtlas_Coordinator.swift` | Singleton, notification listener, public API |
| Body Map | `Views/SiteAtlas/SiteAtlas_BodyMapView.swift` | Swipeable front/back body map with age-colored pins, tap-to-place via UIKit gesture |
| Selection Sheet | `Views/SiteAtlas/SiteAtlas_SiteSelectionSheet.swift` | Modal for logging new sites with draggable pin |
| Settings | `Views/SiteAtlas/SiteAtlas_SettingsView.swift` | Next Up recommendations, history, hide/show, edit sheet |
| Assets | `Resources/SiteAtlas/BodyMapFront.png`, `BodyMapBack.png` | Body outline images |

## Notification Flow

```
DeviceDataManager.pumpManagerWillDeactivate(_:)
    ↓ posts .pumpSiteDeactivated
SiteAtlas_Coordinator receives (via Combine publisher)
    ↓ sets pendingSiteLog = true (on main thread)
SiteAtlas_SettingsView observes coordinator
    ↓ presents SiteAtlas_SiteSelectionSheet
User taps body map → drags pin to adjust → saves → coordinator.logSite(_:)
    ↓ persists via SiteAtlas_Storage
```

## Integration Points (3 files modified)

1. **`Managers/DeviceDataManager.swift`** — Posts `.pumpSiteDeactivated` notification in `pumpManagerWillDeactivate(_:)`
2. **`Managers/LoopDataManager.swift`** — Initializes `SiteAtlas_Coordinator.shared` on launch
3. **`Views/SettingsView.swift`** — Adds `siteAtlasSettingsRow` NavigationLink

## JSON Schema

File location: `Documents/SiteAtlasEntries.json`

```json
{
  "entries": [
    {
      "id": "UUID string",
      "type": "pump" | "sensor",
      "date": "ISO8601 date string",
      "bodySide": "front" | "back",
      "normalizedX": 0.0-1.0,
      "normalizedY": 0.0-1.0,
      "notes": "optional string or null",
      "isHidden": false
    }
  ]
}
```

- Retention: 365 days. Pruning happens on every `loadEntries()` call.
- `isHidden` defaults to `false` for backward compatibility (custom `init(from:)` decoder).

## Age-Based Color System

Pins are color-coded by how long ago the site was placed:

| Days | Color | Meaning |
|------|-------|---------|
| 0-4 | Red | Just placed — avoid |
| 5-9 | Orange | Healing — not ready |
| 10-13 | Yellow | Almost ready |
| 14+ | Green | Safe to reuse |

Implemented via `SiteAtlas_Theme.ageColor(daysSincePlaced:)` — a continuous gradient, not discrete steps.

## Key UI Features

### Next Up Section
Sorted oldest-first. Top entry = recommended next site. Shows days-ago count with age color and "Ready" badge when ≥3 days.

### Hide/Show Entries
- Swipe left → Delete (destructive)
- Swipe right → Hide from Map (orange)
- Hidden entries collected in collapsible "Hidden" section
- Swipe right on hidden entry → Show again (green)
- Hidden entries excluded from body map pins and Next Up list

### Edit Entry Sheet
Tap any history row to edit date/time (graphical DatePicker), site type, and notes. Location (side + coordinates) is read-only.

### Draggable Pins with Visual Feedback
Both the site selection sheet and the settings body map support touch-drag-drop for pins:
- On touch, pin expands from 22pt to 110pt with a 130pt colored halo — unmistakable "grabbed" feedback
- Expansion animates in/out over 150ms via `.easeOut`
- Uses `.offset()` instead of `.position()` so the gesture hit area follows the visual position (`.position()` doesn't move hit testing in SwiftUI)
- 44x44pt `.contentShape(Rectangle())` for reliable touch targeting

### Proximity-Based Color During Drag (Selection Sheet)
When dragging a new pin on the placement sheet, the pin color shifts in real-time based on proximity to existing sites:
- **Green** = safe zone, far from recent sites
- **Yellow** = getting close to a recent site
- **Red** = danger zone, on top of a recently-used area
- Factors in both physical distance (normalized coords) AND recency (14+ day old sites don't trigger red)
- Existing pins on the same body side are shown as faded icons for reference

### Body Bounds Clamping
Pins cannot be placed outside the body silhouette. A body profile defines valid horizontal bounds at 14 Y-positions (head through ankles). If a pin is dropped outside this boundary — via tap or drag — it snaps to the nearest valid point with a spring animation.

### Swipeable Body Map
Front/back views in a `TabView(.page)` — swipe the image itself to flip. Uses `UITapGestureRecognizer` (via `UIViewRepresentable`) for pin placement so swipe gestures pass through to TabView.

### Pinned Save Button
The "Save Site" button on the selection sheet is pinned to the bottom of the screen (outside the `ScrollView`), always visible regardless of scroll position.

## Adding New Site Types

1. Add a case to `SiteAtlas_SiteType` enum in `SiteAtlas_Models.swift`
2. Provide `displayName`, `iconName` (SF Symbol), and `color`
3. The rest of the UI automatically picks it up via `CaseIterable`

## Theme Colors

- Primary (pump): `rgb(230, 126, 34)` — burnt orange
- Sensor: `rgb(41, 128, 185)` — steel blue
- Age scale: red → orange → yellow → green (14-day transition)
- Defined in `SiteAtlas_Theme` enum
