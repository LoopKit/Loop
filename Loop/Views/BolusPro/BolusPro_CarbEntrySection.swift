//
//  BolusPro_CarbEntrySection.swift
//  Loop
//
//  BolusPro — Toggle + slider + macro readout, embedded inside Loop's
//  CarbEntryView so the user can opt in to dual-entry dosing per meal.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Slot-in view rendered inside CarbEntryView's main `Form`/`List`.
/// All state is held by the parent `CarbEntryViewModel` and passed in
/// via `@Binding`s, so this view stays stateless and easy to test.
struct BolusPro_CarbEntrySection: View {

    @Binding var state: BolusProEntryState

    /// Primary carb amount in grams (from CarbEntryViewModel.carbsQuantity).
    /// Used to render the primary-entry preview row.
    var primaryCarbsGrams: Double?

    /// Primary absorption time in seconds (from CarbEntryViewModel).
    /// Used to render the primary-entry preview row.
    var primaryAbsorptionTime: TimeInterval

    /// Required for the (i) sheet to lift up the parent context if needed.
    var onboardingNeeded: Bool = !BolusPro_FeatureFlags.onboardingCompleted

    @State private var showOnboarding = false
    @State private var showInfo = false

    var body: some View {
        VStack(spacing: 0) {
            toggleRow

            if state.enabled {
                Divider().padding(.leading, 16)

                if shouldShowManualMacros {
                    BolusPro_ManualMacroFields(
                        fatGrams: $state.macros.fatGrams,
                        proteinGrams: $state.macros.proteinGrams
                    )
                    .padding(.horizontal, 16)

                    Divider().padding(.leading, 16)
                }

                sliderBlock
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .sheet(isPresented: $showOnboarding) {
            BolusPro_OnboardingView()
        }
        .sheet(isPresented: $showInfo) {
            BolusPro_InfoSheet()
        }
        .onChange(of: state.enabled) { newValue in
            if newValue, onboardingNeeded, !BolusPro_FeatureFlags.onboardingCompleted {
                showOnboarding = true
            }
        }
    }

    // MARK: - Sub-views

    private var toggleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.halffull")
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                .font(.body)
            Text("BolusPro")
                .font(.body)
            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                    .font(.body)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About BolusPro")

            Spacer()

            if state.enabled, fpu.fpuScore >= 0.1 {
                Text(String(format: "%.1f FPU", fpu.fpuScore))
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 230/255, green: 188/255, blue: 60/255))
                    .clipShape(Capsule())
            }

            Toggle("", isOn: $state.enabled)
                .labelsHidden()
                .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sliderBlock: some View {
        VStack(spacing: 14) {

            // Header — frames the section as "this is what will get saved"
            Text("BolusPro splits this meal into two timed carb entries:")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            primaryEntryRow

            timelineConnector

            fpuEntryRow

            Slider(value: $state.sliderCoverage, in: 0...1, step: 0.05)
                .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))
                .padding(.top, 6)

            HStack {
                Text("Off").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("\(Int(state.sliderCoverage * 100))% of computed FPU bonus")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Full").font(.caption2).foregroundColor(.secondary)
            }

            // Footer caption — single sentence that ties the two rows
            // and the slider together in plain language.
            footerCaption
        }
    }

    // MARK: - Entry Preview Rows

    private var primaryEntryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(number: "1", tinted: false)
            Text("🍴").font(.title3).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("BOLUS NOW")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text("·").foregroundColor(.secondary).font(.caption2)
                    Text("Your carbs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("\(primaryCarbsLabel) · absorbs over \(primaryAbsorptionLabel)")
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
    }

    private var fpuEntryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(number: "2", tinted: true)
            Text("🥩").font(.title3).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(fpuStartLabel.uppercased())
                        .font(.caption2.bold())
                        .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                    Text("·").foregroundColor(.secondary).font(.caption2)
                    Text("Protein/fat tail (BolusPro)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Text(bonusGramsLabel)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                    Text("· absorbs over \(BolusPro_FeatureFlags.fpuAbsorptionHours) hr")
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Numbered circle badge to make "two entries" visually obvious.
    private func stepBadge(number: String, tinted: Bool) -> some View {
        let brand = Color(red: 230/255, green: 188/255, blue: 60/255)
        return Text(number)
            .font(.caption2.bold())
            .foregroundColor(tinted ? .white : .secondary)
            .frame(width: 18, height: 18)
            .background(
                Circle().fill(tinted ? brand : Color.secondary.opacity(0.18))
            )
    }

    /// Vertical dotted line drawn between the two preview rows so the user
    /// reads them as a visual sequence (1 → 2) rather than a list.
    private var timelineConnector: some View {
        HStack(spacing: 0) {
            // Indent to align with the badge column above
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 1, height: 14)
                .padding(.leading, 8)
            Spacer()
        }
    }

    private var footerCaption: some View {
        Text("Loop doses against both entries the same way it doses any meal. Drag the slider to scale only the protein/fat tail — all the way left skips BolusPro for this meal.")
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    // MARK: - Computed

    private var fpu: BolusProFPUResult {
        BolusPro_FPUCalculator.calculate(from: state)
    }

    private var bonusGramsLabel: String {
        if !state.macros.hasMacros { return "+0 g" }
        return String(format: "+%.0f g", fpu.bonusGrams)
    }

    private var primaryCarbsLabel: String {
        guard let q = primaryCarbsGrams, q > 0 else { return "— g" }
        return String(format: "%.0f g", q)
    }

    /// Convert seconds → "Xh Ym" / "Xh" label, matching Loop's absorption display.
    private var primaryAbsorptionLabel: String {
        let totalMinutes = Int(primaryAbsorptionTime / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 { return "\(hours) hr \(minutes) min" }
        if hours > 0 { return "\(hours) hr" }
        return "\(minutes) min"
    }

    private var fpuStartLabel: String {
        let mins = BolusPro_FeatureFlags.fpuDelayMinutes
        return mins == 0 ? "Now" : "Starts in \(mins) min"
    }

    private var shouldShowManualMacros: Bool {
        BolusPro_FeatureFlags.showManualMacroFields && !state.macrosFromFoodFinder
    }
}
