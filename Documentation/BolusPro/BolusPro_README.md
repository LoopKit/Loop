# BolusPro

**Protein & fat-aware bolusing for long absorption meals.**

## What it does

When you eat pizza, burgers, fried foods, or rich pastas, fat and protein turn into glucose 2–6 hours after the meal — long after a normal carb bolus has finished. BolusPro covers that delayed rise automatically by creating a second timed carb entry behind the scenes. Loop sees both entries and spreads its insulin coverage across the full meal duration. **You're not bolusing twice** — you're giving Loop a more accurate picture of when the insulin will be needed.

## How to use it

1. **Enable BolusPro** in Settings → BolusPro. (Master toggle is OFF by default.)
2. **Open Add Carb Entry** as you normally would — directly, or via FoodFinder.
3. **The BolusPro section appears** below Absorption Time. For meals with fat & protein high enough to trigger the auto-detect threshold (default ≥1.5 FPU), the toggle flips on automatically.
4. **Adjust the slider** — moves between 0% (no protein/fat coverage) and 100% (full computed bonus). Default = 100% of your configured coverage factor (50%).
5. **Hit Continue.** Loop saves two carb entries: your primary carbs, and the BolusPro tail (sized for your protein/fat, set to a longer absorption window). Both feed Loop's normal closed-loop dosing.

## When to use it

- Meals with **>40g fat or >25g protein** (or anything labeled "high FPU" by FoodFinder).
- Pizza, burgers, fried foods, rich curries, cheesy pastas, fatty steaks.

## When to skip it

- Low-fat carb meals: rice + chicken breast, fruit, oatmeal, sandwiches with lean protein.
- The slider can be turned down to 0% per-meal if you change your mind.

## Configuring it

Settings → BolusPro:

| Setting | Default | What it does |
|---|---|---|
| **Enable BolusPro** | OFF | Master toggle. Off → BolusPro UI never appears. |
| **Auto-enable for high-FPU meals** | ON | Flips per-entry toggle on when FoodFinder detects FPU ≥ threshold. |
| **Trigger threshold** | 1.5 FPU | The auto-detect threshold. Lower = more meals trigger BolusPro. |
| **Show fat & protein fields for manual entries** | ON | When ON and no AI macros present, manual fat/protein input fields appear. |
| **Coverage factor** *(advanced)* | 50% | How aggressively the FPU bonus carb is sized. Higher = more insulin coverage. |
| **FPU delay** *(advanced)* | 60 min | Minutes after the meal before the bonus carb begins absorbing. |
| **FPU absorption** *(advanced)* | 6 hr | How long Loop spreads insulin coverage for the bonus. |

The advanced knobs match Trio's out-of-the-box behavior. Most users never need to change them.

## Watching the first few times

BolusPro is conservative by default, but every body responds differently to fat and protein. Monitor your glucose 2–6 hours after high-FPU meals. If you trend high, dial Coverage factor up. If you trend low, dial it down.

## Behavior Insights

After ~3 BolusPro meals, **LoopInsights → Behavior Insights** starts showing patterns:
- **Adoption rate** — what fraction of meals you use BolusPro on
- **Slider drift** — your typical slider position (e.g., 65% vs. system default 100%)
- **Auto-detect override** — how often you turn off auto-flagged meals
- **Bonus distribution** — average and peak FPU bonus across recent meals
- **Macros source mix** — where your fat/protein values come from (AI, product, manual)

## FAQ

**Q: Where does the FPU number come from?**
A: It's the strict-Warsaw definition: 1 FPU = 100 kcal of fat + protein (`fat × 9 + protein × 4`). It's used for the threshold check and the on-screen pill, not for the dosing math.

**Q: How is the bonus carb amount calculated?**
A: Trio's modified-Pankowska formula: `bonus = (fat × 0.9 + protein × 0.4) × coverage% × slider%`. So 18g fat + 25g protein at 50% coverage and 100% slider = `(16.2 + 10) × 0.5 × 1.0 = 13g` bonus carbs.

**Q: Why a meat emoji on the second entry?**
A: 🥩 marks BolusPro-derived entries in your carb history so you can tell them from real carbs at a glance.

**Q: What if my meal turns out smaller than estimated?**
A: V1 is manual-cancel only. Edit or delete the secondary carb entry (the 🥩 one) like any other carb entry in Loop. V2 may add a one-tap "cancel BolusPro tail" action.

**Q: Does BolusPro work without FoodFinder?**
A: Yes. With "Show fat & protein fields for manual entries" on, a manual carb entry will surface fat/protein inputs when you toggle BolusPro on. Type the values yourself.

**Q: Does this share my data?**
A: BolusPro snapshots feed DataLayer (gated by your existing DataLayer consent). They also drive your local Behavior Insights view — that data never leaves your device.

## Privacy

- All BolusPro UserDefaults keys are local-only.
- Behavior Insights snapshots are stored in UserDefaults on-device — never uploaded.
- DataLayer ingest of BolusPro snapshots respects your existing DataLayer consent for the "Carbs and Meals" category.

---

*BolusPro is part of Loop's AllFeatures fork. See [BolusPro_DEVELOPER.md](BolusPro_DEVELOPER.md) for architecture and developer notes.*
