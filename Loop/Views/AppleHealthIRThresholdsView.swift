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

    @State private var sleepExpanded = false
    @State private var stepsExpanded = false
    @State private var hrvExpanded = false
    @State private var exerciseExpanded = false
    @State private var rhrExpanded = false
    @State private var clampExpanded = false

    init(service: AppleHealthIRServiceProtocol? = nil) {
        self.service = service
        _draft = State(initialValue: service?.thresholds ?? AppleHealthIRThresholds.load())
    }

    var body: some View {
        List {
            Section {
                DisclosureGroup(isExpanded: $sleepExpanded) {
                    metricGrid(
                        thresholds: [
                            ("T1 (hr)", $draft.sleepT1), ("T2 (hr)", $draft.sleepT2),
                            ("T3 (hr)", $draft.sleepT3), ("T4 (hr)", $draft.sleepT4)
                        ],
                        effects: [
                            ("Zone 1 (%)", $draft.sleepE1), ("Zone 2 (%)", $draft.sleepE2),
                            ("Zone 3 (%)", $draft.sleepE3), ("Zone 4 (%)", $draft.sleepE4)
                        ]
                    )
                } label: {
                    metricLabel(
                        name: NSLocalizedString("Sleep", comment: "Settings metric label"),
                        summary: "\(format(draft.sleepT1))–\(format(draft.sleepT4)) hr"
                    )
                }

                DisclosureGroup(isExpanded: $stepsExpanded) {
                    metricGrid(
                        thresholds: [
                            ("T1 (steps)", $draft.stepsT1), ("T2 (steps)", $draft.stepsT2),
                            ("T3 (steps)", $draft.stepsT3), ("T4 (steps)", $draft.stepsT4)
                        ],
                        effects: [
                            ("Zone 1 (%)", $draft.stepsE1), ("Zone 2 (%)", $draft.stepsE2),
                            ("Zone 3 (%)", $draft.stepsE3), ("Zone 4 (%)", $draft.stepsE4)
                        ]
                    )
                } label: {
                    metricLabel(
                        name: NSLocalizedString("Steps", comment: "Settings metric label"),
                        summary: "\(formatInt(draft.stepsT1))–\(formatInt(draft.stepsT4))"
                    )
                }

                DisclosureGroup(isExpanded: $hrvExpanded) {
                    metricGrid(
                        thresholds: [
                            ("T1 (ms)", $draft.hrvT1), ("T2 (ms)", $draft.hrvT2),
                            ("T3 (ms)", $draft.hrvT3), ("T4 (ms)", $draft.hrvT4)
                        ],
                        effects: [
                            ("Zone 1 (%)", $draft.hrvE1), ("Zone 2 (%)", $draft.hrvE2),
                            ("Zone 3 (%)", $draft.hrvE3), ("Zone 4 (%)", $draft.hrvE4)
                        ]
                    )
                } label: {
                    metricLabel(
                        name: NSLocalizedString("HRV", comment: "Settings metric label"),
                        summary: "\(formatInt(draft.hrvT1))–\(formatInt(draft.hrvT4)) ms"
                    )
                }

                DisclosureGroup(isExpanded: $exerciseExpanded) {
                    metricGrid(
                        thresholds: [
                            ("T1 (min)", $draft.exerciseT1), ("T2 (min)", $draft.exerciseT2),
                            ("T3 (min)", $draft.exerciseT3), ("T4 (min)", $draft.exerciseT4)
                        ],
                        effects: [
                            ("Zone 1 (%)", $draft.exerciseE1), ("Zone 2 (%)", $draft.exerciseE2),
                            ("Zone 3 (%)", $draft.exerciseE3), ("Zone 4 (%)", $draft.exerciseE4)
                        ]
                    )
                } label: {
                    metricLabel(
                        name: NSLocalizedString("Exercise", comment: "Settings metric label"),
                        summary: "\(formatInt(draft.exerciseT1))–\(formatInt(draft.exerciseT4)) min"
                    )
                }

                DisclosureGroup(isExpanded: $rhrExpanded) {
                    metricGrid(
                        thresholds: [
                            ("T1 (bpm)", $draft.rhrT1), ("T2 (bpm)", $draft.rhrT2),
                            ("T3 (bpm)", $draft.rhrT3), ("T4 (bpm)", $draft.rhrT4)
                        ],
                        effects: [
                            ("Zone 1 (%)", $draft.rhrE1), ("Zone 2 (%)", $draft.rhrE2),
                            ("Zone 3 (%)", $draft.rhrE3), ("Zone 4 (%)", $draft.rhrE4)
                        ]
                    )
                } label: {
                    metricLabel(
                        name: NSLocalizedString("Resting HR", comment: "Settings metric label"),
                        summary: "\(formatInt(draft.rhrT1))–\(formatInt(draft.rhrT4)) bpm"
                    )
                }
            } header: {
                Text(NSLocalizedString("Biometric Thresholds", comment: "Settings section header"))
            }

            Section {
                DisclosureGroup(isExpanded: $clampExpanded) {
                    HStack {
                        Text(NSLocalizedString("Min multiplier", comment: "Settings label")).font(.subheadline)
                        Spacer()
                        DecimalField(label: "", value: $draft.multiplierMin)
                    }
                    HStack {
                        Text(NSLocalizedString("Max multiplier", comment: "Settings label")).font(.subheadline)
                        Spacer()
                        DecimalField(label: "", value: $draft.multiplierMax)
                    }
                } label: {
                    metricLabel(
                        name: NSLocalizedString("Multiplier Clamp", comment: "Settings metric label"),
                        summary: "\(format(draft.multiplierMin)) – \(format(draft.multiplierMax))"
                    )
                }
            } header: {
                Text(NSLocalizedString("Output", comment: "Settings section header"))
            }

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
                sleepExpanded = false
                stepsExpanded = false
                hrvExpanded = false
                exerciseExpanded = false
                rhrExpanded = false
                clampExpanded = false
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
        }
    }

    // MARK: - Helper views

    @ViewBuilder
    private func metricLabel(name: String, summary: String) -> some View {
        HStack {
            Text(name).font(.subheadline)
            Spacer()
            Text(summary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func metricGrid(
        thresholds: [(String, Binding<Double>)],
        effects: [(String, Binding<Double>)]
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(NSLocalizedString("Thresholds", comment: "Grid column header"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(NSLocalizedString("Effects", comment: "Grid column header"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)

            ForEach(0..<thresholds.count, id: \.self) { i in
                HStack(spacing: 8) {
                    DecimalField(label: thresholds[i].0, value: thresholds[i].1)
                        .frame(maxWidth: .infinity)
                    Divider()
                    EffectField(label: effects[i].0, value: effects[i].1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 4)
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

    private func format(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }

    private func formatInt(_ v: Double) -> String { String(Int(v)) }
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

private struct EffectField: View {
    let label: String
    @Binding var value: Double
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .foregroundColor(value >= 0 ? .red : .green)
                .onAppear { text = String(format: "%+.1f", value) }
                .onChange(of: text) { newText in
                    if let parsed = Double(newText) { value = parsed }
                }
        }
    }
}
