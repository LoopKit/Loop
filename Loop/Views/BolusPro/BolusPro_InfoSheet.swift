//
//  BolusPro_InfoSheet.swift
//  Loop
//
//  BolusPro — In-context (i) explainer presented from CarbEntryView,
//  Settings, and the first-run onboarding.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct BolusPro_InfoSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    header

                    section(
                        title: "Why a second slider?",
                        body: "Fat and protein from your meal slowly turn into glucose 2–6 hours after you eat — long after a normal carb bolus has finished. For pizza, burgers, or fried foods, this late rise can push your sugar high overnight or 4 hours into a movie."
                    )

                    section(
                        title: "What does the slider do?",
                        body: "It creates a second carb entry behind the scenes — sized to match the protein/fat effect, set to a longer absorption window. Loop sees both entries and spreads its insulin coverage across the full meal, so you don't have to bolus twice."
                    )

                    calloutBox

                    section(
                        title: "When to use it",
                        body: "Meals with more than ~40g fat or ~25g protein, or anything labeled \"high FPU\" by FoodFinder. Skip it for low-fat carb meals (rice + chicken breast, fruit, oatmeal)."
                    )

                    section(
                        title: "How the math works",
                        body: "BolusPro uses Trio's gram formula: bonus grams = (fat × 0.9 + protein × 0.4) × your coverage factor. The default 50% coverage matches Trio's out-of-the-box setting and works for most users. You can tune coverage, delay, and absorption time in Settings → BolusPro."
                    )

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("About BolusPro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "drop.halffull")
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
            VStack(alignment: .leading, spacing: 2) {
                Text("BolusPro")
                    .font(.title2).bold()
                Text("Protein & fat-aware bolusing for long absorption meals")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.body).foregroundColor(.primary.opacity(0.85))
        }
    }

    private var calloutBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("You're not bolusing twice.", systemImage: "info.circle.fill")
                .font(.subheadline.bold())
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
            Text("You're giving Loop a more accurate picture of when the insulin will be needed. Loop handles the dosing.")
                .font(.footnote)
                .foregroundColor(.primary.opacity(0.85))
        }
        .padding(14)
        .background(Color(red: 230/255, green: 188/255, blue: 60/255).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Reusable (i) button

/// Drop-in info button used inline next to BolusPro labels.
struct BolusPro_InfoButton: View {
    @State private var presented = false

    var body: some View {
        Button {
            presented = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                .font(.body)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presented) {
            BolusPro_InfoSheet()
        }
    }
}

// MARK: - Trigger Threshold Tooltip

/// Focused explainer for the auto-detect trigger threshold slider.
/// Presented from Settings → BolusPro when the user taps the (i) next
/// to "Trigger threshold". Smaller and more targeted than the full
/// `BolusPro_InfoSheet`.
struct BolusPro_TriggerThresholdInfoSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars.inverse")
                            .font(.title2)
                            .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                        Text("Trigger Threshold")
                            .font(.title3).bold()
                    }

                    Text("When FoodFinder analyzes a meal, it computes a Fat-Protein Unit (FPU) score. **1 FPU = 100 kcal of fat or protein**. If the score is at or above this threshold, BolusPro flips on automatically — you don't have to remember to toggle it for fatty meals.")
                        .font(.body)
                        .foregroundColor(.primary.opacity(0.85))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Suggested values")
                            .font(.headline)

                        thresholdRow(
                            value: "0.5 FPU",
                            label: "Very sensitive",
                            detail: "Catches almost any meal with fat or protein. May feel aggressive for everyday low-fat carbs."
                        )
                        thresholdRow(
                            value: "1.5 FPU",
                            label: "Default — balanced",
                            detail: "Catches pizza, burgers, fried foods, fatty pastas. Skips lean meals, fruit, oatmeal."
                        )
                        thresholdRow(
                            value: "2.5+ FPU",
                            label: "Conservative",
                            detail: "Only triggers on heavy fat-and-protein meals (large pizza, ribeye + sides, fried chicken plate)."
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Tip", systemImage: "lightbulb.fill")
                            .font(.subheadline.bold())
                            .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                        Text("If you find BolusPro turning on for meals that don't need it, raise this. If you keep manually flipping it on, lower it.")
                            .font(.footnote)
                            .foregroundColor(.primary.opacity(0.85))
                    }
                    .padding(14)
                    .background((Color(red: 230/255, green: 188/255, blue: 60/255)).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Trigger Threshold")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func thresholdRow(value: String, label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
