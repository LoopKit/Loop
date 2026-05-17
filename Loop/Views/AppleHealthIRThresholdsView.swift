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
        Section(header: Text(NSLocalizedString("Sleep (hours)", comment: "Section header"))) {
            DecimalField(label: "T1 threshold (hr)", value: $draft.sleepT1)
            DecimalField(label: "T2 threshold (hr)", value: $draft.sleepT2)
            DecimalField(label: "T3 threshold (hr)", value: $draft.sleepT3)
            DecimalField(label: "T4 threshold (hr)", value: $draft.sleepT4)
            DecimalField(label: "Zone 1 effect (%)", value: $draft.sleepE1)
            DecimalField(label: "Zone 2 effect (%)", value: $draft.sleepE2)
            DecimalField(label: "Zone 3 effect (%)", value: $draft.sleepE3)
            DecimalField(label: "Zone 4 effect (%)", value: $draft.sleepE4)
        }
    }

    private var stepsSection: some View {
        Section(header: Text(NSLocalizedString("Steps", comment: "Section header"))) {
            DecimalField(label: "T1 threshold (steps)", value: $draft.stepsT1)
            DecimalField(label: "T2 threshold (steps)", value: $draft.stepsT2)
            DecimalField(label: "T3 threshold (steps)", value: $draft.stepsT3)
            DecimalField(label: "T4 threshold (steps)", value: $draft.stepsT4)
            DecimalField(label: "Zone 1 effect (%)", value: $draft.stepsE1)
            DecimalField(label: "Zone 2 effect (%)", value: $draft.stepsE2)
            DecimalField(label: "Zone 3 effect (%)", value: $draft.stepsE3)
            DecimalField(label: "Zone 4 effect (%)", value: $draft.stepsE4)
        }
    }

    private var hrvSection: some View {
        Section(header: Text(NSLocalizedString("HRV (ms)", comment: "Section header"))) {
            DecimalField(label: "T1 threshold (ms)", value: $draft.hrvT1)
            DecimalField(label: "T2 threshold (ms)", value: $draft.hrvT2)
            DecimalField(label: "T3 threshold (ms)", value: $draft.hrvT3)
            DecimalField(label: "T4 threshold (ms)", value: $draft.hrvT4)
            DecimalField(label: "Zone 1 effect (%)", value: $draft.hrvE1)
            DecimalField(label: "Zone 2 effect (%)", value: $draft.hrvE2)
            DecimalField(label: "Zone 3 effect (%)", value: $draft.hrvE3)
            DecimalField(label: "Zone 4 effect (%)", value: $draft.hrvE4)
        }
    }

    private var exerciseSection: some View {
        Section(header: Text(NSLocalizedString("Exercise (minutes)", comment: "Section header"))) {
            DecimalField(label: "T1 threshold (min)", value: $draft.exerciseT1)
            DecimalField(label: "T2 threshold (min)", value: $draft.exerciseT2)
            DecimalField(label: "T3 threshold (min)", value: $draft.exerciseT3)
            DecimalField(label: "T4 threshold (min)", value: $draft.exerciseT4)
            DecimalField(label: "Zone 1 effect (%)", value: $draft.exerciseE1)
            DecimalField(label: "Zone 2 effect (%)", value: $draft.exerciseE2)
            DecimalField(label: "Zone 3 effect (%)", value: $draft.exerciseE3)
            DecimalField(label: "Zone 4 effect (%)", value: $draft.exerciseE4)
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
