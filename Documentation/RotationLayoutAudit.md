# Rotation layout audit

This audit addresses [Loop issue #2477](https://github.com/LoopKit/Loop/issues/2477), particularly the portrait → landscape → portrait sequence, and checks the related reports in [issue #1610](https://github.com/LoopKit/Loop/issues/1610).

## Findings and fixes

The prediction input cells copied `separatorInset.left` into both horizontal content margins during layout. The separator inset already incorporates UIKit's current safe area and readable margins. Saving that computed value as an explicit minimum margin prevented UIKit from reducing it on return to portrait. A simulator reproduction retained an 82-point margin instead of its original 20 points.

Remove these assignments and let UIKit manage the content margins. The existing constraints to `contentView.layoutMarginsGuide` continue to follow the current layout. Apply the same fix to every occurrence in the workspace:

| Component | Screens affected |
| --- | --- |
| `PredictionInputEffectTableViewCell` | Predicted Glucose input rows |
| Prediction chart cell configuration | Predicted Glucose chart description and eventual glucose label |
| `PotentialCarbEntryTableViewCell` | Legacy potential carb-entry rows |
| `SwitchTableViewCell` | Prediction settings, temporary overrides, transmitter settings, mock pump/CGM/service settings, and subclasses |
| `SegmentedControlTableViewCell` | Mock pump settings |
| `RileyLinkDeviceTableViewCell` | RileyLink device selection and setup |

The setup footer had a separate size invalidation problem: it recalculated only when table content height changed. Fixed-height rows do not change height during rotation, so the Continue button could retain its portrait position in landscape. `SetupTableViewController` now calculates the footer size from the current table width, available height, and content height excluding the existing footer. It assigns the footer only when its size or identity changes. This covers RileyLink setup, transmitter setup, and the legacy Minimed setup screens.

## Coverage

The source audit covered Swift, storyboard, and nib layout code throughout the workspace, including shared components used by pump, CGM, service, and onboarding plugins. It checked separator-to-margin assignments, stored screen dimensions, manual frames, safe-area handling, chart size caches, and rotation/layout callbacks.

| Screen family | Review |
| --- | --- |
| Status, Predicted Glucose, Carb Absorption, insulin delivery | Shared chart containers regenerate for their current bounds; prediction margin assignments removed |
| Carb entry, bolus, manual dose, simple bolus | No separator-to-margin assignment remains; bolus and manual dose retain their existing portrait restriction |
| Settings and therapy editors, schedules, alerts, authentication, support/export | Shared switch-cell assignments removed; other rows use UIKit/SwiftUI layout and margin constraints |
| Presets, training/media, favorite foods, statistics, informational screens | No matching persistent margin assignment found |
| Pump/CGM/service settings and onboarding | Shared switch, segmented, RileyLink, and setup-footer fixes applied at their common implementations |

The audit is a source review of every screen family, not a claim that every hardware-dependent screen was exercised with a connected device. Predicted Glucose was also inspected in the running iPhone simulator before rotation, in landscape, and after returning to portrait; the input labels and separators returned to their original alignment. This visual check used an unconfigured test app, so it does not validate clinical data rendering.

## Validation

Validation completed with Xcode 27: the workspace build succeeded. Simulator checks covered all five affected cell classes, including repeated rotation round trips, cell reuse, both landscape safe areas, right-to-left layout, and wider readable layouts. Setup-footer checks verified the available height through portrait, landscape, and portrait again with unchanged row heights. These checks used temporary verification code; the change contains no new test sources or test-project references.

Independent simulator reproductions confirmed the stuck margins and footer height before the fixes and their restoration afterward. Project-file validation and whitespace checks also passed.

For manual checks, open each screen in portrait, rotate in both landscape directions, return to portrait, scroll to reveal reused rows, and verify label/separator alignment and navigation controls. For setup screens, also verify that Continue remains reachable in landscape.

## Issue #1610 verification

The current `next-dev`-based changes were rebuilt successfully with Xcode 27 and checked on an iPhone 17 Pro simulator running iOS 26.5.

| Report | Result |
| --- | --- |
| Therapy Settings has a white strip in the landscape safe area | Not reproduced in either landscape direction. The production `TherapySettingsView` and shared `CardList` show the grouped background through both horizontal safe areas. The original report explicitly occurred on a physical device only; that case still requires physical-device confirmation. |
| Predicted Glucose spacing after portrait → landscape → portrait | Passes the previously recorded simulator round trip with the margin fixes. |
| Carbohydrates spacing after portrait → landscape → portrait | Passes a real simulator rotation with production storyboard prototypes and cell classes. Chart title, legend, description, totals, and entry labels recover their original horizontal bounds, compared with a tolerance of 0.5 points. No additional Carbohydrates margin change was needed. |
| Open Predicted Glucose in landscape, then rotate to portrait | Passes in the rebuilt Loop app. The first two forecast components align with the remaining components and the separators. |
| Bolus can open in landscape but cannot rotate from portrait to landscape | Landscape rotation remains restricted by `BolusEntryView`'s explicit `.supportedInterfaceOrientations(.portrait)`. The current changes do not remove that restriction, so this comment cannot be described as fixed. |

Therapy Settings and Carbohydrates were checked in an isolated temporary simulator app using production views, storyboard constraints, cell classes, and row-height estimates with synthetic display values. This avoids configuring a pump or changing clinical settings. The Carbohydrates fixture checks layout, including its chart text, rather than the data-fetching controller or glucose-effect rendering. The unconfigured Loop app could not perform that check directly: opening Carbohydrates encountered an unrelated missing carb-ratio-history crash, and Therapy Settings is hidden until a pump is configured. Predicted Glucose was checked directly in Loop. No new tests or test-project references were added to the repository.
