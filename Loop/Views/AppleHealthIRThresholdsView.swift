//
//  AppleHealthIRThresholdsView.swift
//  Loop
//

import SwiftUI

struct AppleHealthIRThresholdsView: View {
    private let service: AppleHealthIRServiceProtocol?
    @State private var draft: AppleHealthIRThresholds
    @State private var validationError: String?
    @State private var showResetConfirmation = false

    init(service: AppleHealthIRServiceProtocol? = nil) {
        self.service = service
        _draft = State(initialValue: service?.thresholds ?? AppleHealthIRThresholds.load())
    }

    var body: some View {
        List {
            sleepSection
            stepsSection
            hrvSection
            exerciseSection
            clampSection
            if let error = validationError {
                Section {
                    Text(error).foregroundColor(.red).font(.footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("IR Thresholds", comment: "Navigation title"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Save", comment: "Save button")) { save() }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(NSLocalizedString("Reset", comment: "Reset button")) {
                    showResetConfirmation = true
                }
            }
        }
        .confirmationDialog(
            NSLocalizedString("Reset to defaults?", comment: "Reset confirmation title"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Reset", comment: "Reset confirm button"), role: .destructive) {
                draft = .default
                validationError = nil
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
        }
    }

    private var sleepSection: some View {
        Section(header: Text(NSLocalizedString("Sleep", comment: "Section header"))) {
            DecimalField(label: "Severe threshold (hours)", value: $draft.sleepSevereThreshold)
            DecimalField(label: "Mild threshold (hours)", value: $draft.sleepMildThreshold)
            DecimalField(label: "Severe effect (%)", value: $draft.sleepSevereEffect)
        }
    }

    private var stepsSection: some View {
        Section(header: Text(NSLocalizedString("Steps", comment: "Section header"))) {
            DecimalField(label: "Low min (steps)", value: $draft.stepsLowMin)
            DecimalField(label: "Medium min (steps)", value: $draft.stepsMediumMin)
            DecimalField(label: "High min (steps)", value: $draft.stepsHighMin)
            DecimalField(label: "Low effect (%)", value: $draft.stepsLowEffect)
            DecimalField(label: "Medium effect (%)", value: $draft.stepsMediumEffect)
            DecimalField(label: "High effect (%)", value: $draft.stepsHighEffect)
        }
    }

    private var hrvSection: some View {
        Section(header: Text(NSLocalizedString("HRV", comment: "Section header"))) {
            DecimalField(label: "Very low max (ms)", value: $draft.hrvVeryLowMax)
            DecimalField(label: "Low max (ms)", value: $draft.hrvLowMax)
            DecimalField(label: "Normal max (ms)", value: $draft.hrvNormalMax)
            DecimalField(label: "Very low effect (%)", value: $draft.hrvVeryLowEffect)
            DecimalField(label: "Low effect (%)", value: $draft.hrvLowEffect)
            DecimalField(label: "Normal effect (%)", value: $draft.hrvNormalEffect)
            DecimalField(label: "High effect (%)", value: $draft.hrvHighEffect)
        }
    }

    private var exerciseSection: some View {
        Section(header: Text(NSLocalizedString("Exercise", comment: "Section header"))) {
            DecimalField(label: "Min threshold (min)", value: $draft.exerciseMinThreshold)
            DecimalField(label: "Moderate max (min)", value: $draft.exerciseModerateMax)
            DecimalField(label: "Substantial max (min)", value: $draft.exerciseSubstantialMax)
            DecimalField(label: "Moderate effect (%)", value: $draft.exerciseModerateEffect)
            DecimalField(label: "Substantial effect (%)", value: $draft.exerciseSubstantialEffect)
            DecimalField(label: "Heavy effect (%)", value: $draft.exerciseHeavyEffect)
        }
    }

    private var clampSection: some View {
        Section(header: Text(NSLocalizedString("Multiplier Clamp", comment: "Section header"))) {
            DecimalField(label: "Minimum (≥ 0.5)", value: $draft.multiplierMin)
            DecimalField(label: "Maximum (≤ 2.0)", value: $draft.multiplierMax)
        }
    }

    private func save() {
        do {
            try draft.validate()
            draft.save()
            service?.thresholds = draft
            validationError = nil
        } catch {
            validationError = error.localizedDescription
        }
    }
}

private struct DecimalField: View {
    let label: String
    @Binding var value: Double
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .onAppear { text = String(format: "%.1f", value) }
                .onChange(of: text) { newText in
                    if let parsed = Double(newText) { value = parsed }
                }
        }
    }
}
