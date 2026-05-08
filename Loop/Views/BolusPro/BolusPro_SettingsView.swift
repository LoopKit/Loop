//
//  BolusPro_SettingsView.swift
//  Loop
//
//  BolusPro — Settings subpage with master toggle, auto-detection
//  preferences, advanced coverage tuning, and About / Reset actions.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct BolusPro_SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @AppStorage(BolusPro_FeatureFlags.Keys.isEnabled)
    private var isEnabled: Bool = false

    @AppStorage(BolusPro_FeatureFlags.Keys.autoDetectFromFoodFinder)
    private var autoDetectFromFoodFinder: Bool = true

    @AppStorage(BolusPro_FeatureFlags.Keys.showManualMacroFields)
    private var showManualMacroFields: Bool = true

    @AppStorage(BolusPro_FeatureFlags.Keys.coverageFactorPercent)
    private var coverageFactorPercent: Int = 50

    @AppStorage(BolusPro_FeatureFlags.Keys.fpuDelayMinutes)
    private var fpuDelayMinutes: Int = 60

    @AppStorage(BolusPro_FeatureFlags.Keys.fpuAbsorptionHours)
    private var fpuAbsorptionHours: Int = 6

    @AppStorage(BolusPro_FeatureFlags.Keys.triggerThresholdFPU)
    private var triggerThresholdFPU: Double = 1.5

    @AppStorage(BolusPro_FeatureFlags.Keys.onboardingCompleted)
    private var onboardingCompleted: Bool = false

    @State private var showAdvanced = false
    @State private var showAbout = false
    @State private var showOnboarding = false
    @State private var showThresholdInfo = false
    @State private var confirmReset = false

    var body: some View {
        Form {

            masterSection

            if isEnabled {
                autoDetectSection
                advancedSection
                aboutSection
                resetSection
            } else {
                aboutSection
            }
        }
        .navigationTitle("BolusPro")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAbout) { BolusPro_InfoSheet() }
        .sheet(isPresented: $showOnboarding) { BolusPro_OnboardingView() }
        .sheet(isPresented: $showThresholdInfo) { BolusPro_TriggerThresholdInfoSheet() }
        .alert("Reset BolusPro tunables?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                BolusPro_FeatureFlags.resetTunablesToDefaults()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Coverage, delay, absorption, and detection toggles will return to defaults. Your master toggle and onboarding status are unchanged.")
        }
        .onAppear {
            if isEnabled, !onboardingCompleted {
                showOnboarding = true
            }
        }
    }

    // MARK: - Sections

    private var masterSection: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "drop.halffull")
                        .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Enable BolusPro")
                            .font(.body)
                        Text("Protein & fat-aware bolusing for long absorption meals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))
        }
    }

    private var autoDetectSection: some View {
        Section(header: Text("Auto-detection")) {
            Toggle("Auto-enable for high-FPU meals", isOn: $autoDetectFromFoodFinder)
                .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))

            if autoDetectFromFoodFinder {
                HStack {
                    Text("Trigger threshold")
                    Button {
                        showThresholdInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About Trigger Threshold")
                    Spacer()
                    Text(String(format: "%.1f FPU", triggerThresholdFPU))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $triggerThresholdFPU, in: 0.5...3.0, step: 0.1)
                    .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))
            }

            Toggle("Show fat & protein fields for manual entries", isOn: $showManualMacroFields)
                .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))
        }
    }

    private var advancedSection: some View {
        Section(header: Text("Coverage tuning"),
                footer: Text("Defaults match Trio's out-of-the-box behavior. Most users never need to change these.")) {
            DisclosureGroup(isExpanded: $showAdvanced) {
                coverageFactorRow
                delayRow
                absorptionRow
            } label: {
                HStack {
                    Text("Advanced")
                    Spacer()
                    Text("\(coverageFactorPercent)%, \(fpuDelayMinutes)min, \(fpuAbsorptionHours)h")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var coverageFactorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Coverage factor")
                Spacer()
                Text("\(coverageFactorPercent)%")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(coverageFactorPercent) },
                    set: { coverageFactorPercent = Int($0) }
                ),
                in: 10...100,
                step: 5
            )
            .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))
            Text("How aggressively the FPU bonus carb is sized. Higher = more insulin coverage for the late rise.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var delayRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FPU delay")
                Spacer()
                Text("\(fpuDelayMinutes) min")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(fpuDelayMinutes) },
                    set: { fpuDelayMinutes = Int($0) }
                ),
                in: 0...120,
                step: 15
            )
            .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))
            Text("Minutes after the meal that the FPU bonus carb begins absorbing.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var absorptionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FPU absorption")
                Spacer()
                Text("\(fpuAbsorptionHours) h")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(fpuAbsorptionHours) },
                    set: { fpuAbsorptionHours = Int($0) }
                ),
                in: 4...8,
                step: 1
            )
            .tint((Color(red: 230/255, green: 188/255, blue: 60/255)))
            Text("How long Loop spreads insulin coverage for the FPU bonus.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var aboutSection: some View {
        Section {
            Button {
                showAbout = true
            } label: {
                HStack {
                    Label("About BolusPro", systemImage: "info.circle")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                showOnboarding = true
            } label: {
                HStack {
                    Label("Replay onboarding", systemImage: "play.circle")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Text("Reset to defaults")
            }
        }
    }
}
