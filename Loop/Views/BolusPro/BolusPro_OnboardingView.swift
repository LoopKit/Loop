//
//  BolusPro_OnboardingView.swift
//  Loop
//
//  BolusPro — First-run intro shown the first time the user toggles
//  BolusPro on (or opens its Settings page before completing onboarding).
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct BolusPro_OnboardingView: View {

    @Environment(\.dismiss) private var dismiss
    var onGetStarted: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    icon

                    Text("Smarter bolusing for high-fat meals")
                        .font(.title2).bold()

                    Text("Pizza, burgers, fried foods, and rich pastas cause a delayed glucose rise that arrives 2–6 hours after you eat. BolusPro adds a second timed carb entry — automatically — so Loop can cover that late rise without you having to bolus twice.")
                        .font(.body)
                        .foregroundColor(.primary.opacity(0.85))

                    bullet(icon: "1.circle.fill",
                           title: "Toggle BolusPro on the carb entry screen",
                           body: "FoodFinder meals over ~1.5 FPU flip it on automatically. For manual entries, you'll get fields for fat and protein when the toggle is on.")

                    bullet(icon: "2.circle.fill",
                           title: "Adjust the slider to taste",
                           body: "The slider sets how aggressively Loop covers the protein/fat tail. Start at the default — you can dial it up or down once you see how your body responds.")

                    bullet(icon: "3.circle.fill",
                           title: "Loop handles the dosing",
                           body: "BolusPro creates two paired carb entries. Loop's normal closed-loop logic doses against both. No manual second bolus needed.")

                    safetyCallout

                    Spacer(minLength: 18)

                    Button {
                        BolusPro_FeatureFlags.onboardingCompleted = true
                        onGetStarted?()
                        dismiss()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 230/255, green: 188/255, blue: 60/255))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .navigationTitle("BolusPro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        BolusPro_FeatureFlags.onboardingCompleted = true
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color(red: 230/255, green: 188/255, blue: 60/255).opacity(0.18))
                .frame(width: 96, height: 96)
            Image(systemName: "drop.halffull")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func bullet(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(body).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private var safetyCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Watch closely the first few times.", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundColor((Color(red: 230/255, green: 188/255, blue: 60/255)))
            Text("BolusPro is conservative by default, but every body responds differently to fat and protein. Monitor your glucose 2–6 hours after high-FPU meals and tune the coverage factor in Settings if you trend high or low.")
                .font(.footnote)
                .foregroundColor(.primary.opacity(0.85))
        }
        .padding(14)
        .background(Color(red: 230/255, green: 188/255, blue: 60/255).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
