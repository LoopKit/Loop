//
//  LoopInsights_AlcoholLogView.swift
//  Loop
//
//  LoopInsights — Alcohol intake logging UI with hypo risk awareness.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Brand color for all alcohol UI
private let alcoholAmber = Color.orange

/// Alcohol logging UI: shows current level gauge, hypo risk banner, quick-add presets, and entry log.
struct LoopInsights_AlcoholLogView: View {

    @ObservedObject var tracker: LoopInsights_AlcoholTracker
    @State private var customDrinks: String = ""
    @State private var customSource: String = ""
    @State private var showingCustomEntry = false
    @State private var editingEntry: LoopInsightsAlcoholEntry?
    @State private var editDrinks: String = ""
    @State private var editSource: String = ""
    @State private var editTimestamp: Date = Date()
    @Environment(\.dismiss) private var dismiss

    private var currentState: LoopInsightsAlcoholState {
        tracker.currentState()
    }

    var body: some View {
        List {
            currentLevelSection
            if currentState.hypoRiskLevel != .none {
                hypoRiskBanner
            }
            quickAddSection
            if showingCustomEntry {
                customEntrySection
            }
            recentEntriesSection
        }
        .navigationTitle(NSLocalizedString("Alcohol Tracker", comment: "LoopInsights alcohol title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Done", comment: "Done button")) {
                    dismiss()
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            editEntrySheet(entry)
        }
    }

    // MARK: - Current Level

    private var currentLevelSection: some View {
        Section {
            VStack(spacing: 12) {
                // Level gauge
                ZStack {
                    Circle()
                        .stroke(alcoholAmber.opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)

                    let level = min(currentState.currentAlcoholLevel, 5)
                    Circle()
                        .trim(from: 0, to: level / 5)
                        .stroke(gaugeColor(level), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", currentState.currentAlcoholLevel))
                            .font(.title2.weight(.bold))
                            .foregroundColor(gaugeColor(currentState.currentAlcoholLevel))
                        Text("drinks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(NSLocalizedString("Estimated Alcohol Level", comment: "LoopInsights alcohol level label"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if currentState.entriesLast24h > 0 {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", currentState.totalDrinksLast24h))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(alcoholAmber)
                            Text(NSLocalizedString("24h Total", comment: "LoopInsights alcohol 24h total"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        VStack(spacing: 2) {
                            Text(riskDisplayText(currentState.hypoRiskLevel))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(riskColor(currentState.hypoRiskLevel))
                            Text(NSLocalizedString("Hypo Risk", comment: "LoopInsights alcohol hypo risk"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let clearTime = currentState.estimatedClearTime {
                            VStack(spacing: 2) {
                                Text(Self.timeFormatter.string(from: clearTime))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(alcoholAmber)
                                Text(NSLocalizedString("Est. Clear", comment: "LoopInsights alcohol est clear"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Hypo Risk Banner

    private var hypoRiskBanner: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(riskColor(currentState.hypoRiskLevel))
                VStack(alignment: .leading, spacing: 4) {
                    Text(riskBannerTitle(currentState.hypoRiskLevel))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(riskColor(currentState.hypoRiskLevel))
                    Text(riskBannerDetail(currentState))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Quick Add

    private var quickAddSection: some View {
        Section(header: Text(NSLocalizedString("Quick Add", comment: "LoopInsights alcohol quick add header"))) {
            let presets = LoopInsightsAlcoholPreset.defaults
            let columns = [GridItem(.flexible()), GridItem(.flexible())]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(presets) { preset in
                    Button(action: {
                        tracker.logAlcohol(standardDrinks: preset.standardDrinks, source: preset.name)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: preset.icon)
                                .font(.caption)
                                .foregroundColor(alcoholAmber)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(String(format: "%.1f drinks", preset.standardDrinks))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

            Button(action: { showingCustomEntry.toggle() }) {
                HStack {
                    Image(systemName: showingCustomEntry ? "minus.circle" : "plus.circle")
                    Text(NSLocalizedString("Custom Entry", comment: "LoopInsights alcohol custom entry"))
                }
                .font(.subheadline)
                .foregroundColor(alcoholAmber)
            }
        }
    }

    // MARK: - Custom Entry

    private var customEntrySection: some View {
        Section(header: Text(NSLocalizedString("Custom Alcohol Entry", comment: "LoopInsights custom alcohol header"))) {
            TextField(NSLocalizedString("Standard Drinks (e.g. 1.5)", comment: "LoopInsights alcohol amount placeholder"), text: $customDrinks)
                .keyboardType(.decimalPad)
            TextField(NSLocalizedString("Type (e.g. Margarita)", comment: "LoopInsights alcohol source placeholder"), text: $customSource)

            Button(action: {
                if let drinks = Double(customDrinks), drinks > 0 {
                    let source = customSource.isEmpty ? "Custom" : customSource
                    tracker.logAlcohol(standardDrinks: drinks, source: source)
                    customDrinks = ""
                    customSource = ""
                    showingCustomEntry = false
                }
            }) {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("Add Entry", comment: "LoopInsights alcohol add entry"))
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .background(Double(customDrinks) ?? 0 > 0 ? alcoholAmber : Color.gray)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(Double(customDrinks) ?? 0 <= 0)
        }
    }

    // MARK: - Recent Entries

    private var recentEntriesSection: some View {
        Section(header: Text(NSLocalizedString("Recent Entries", comment: "LoopInsights alcohol recent entries"))) {
            if tracker.entries.isEmpty {
                Text(NSLocalizedString("No alcohol entries yet. Tap a preset above to log intake.", comment: "LoopInsights no alcohol entries"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(tracker.entries.prefix(20)) { entry in
                    Button(action: {
                        editDrinks = String(format: "%.1f", entry.standardDrinks)
                        editSource = entry.source
                        editTimestamp = entry.timestamp
                        editingEntry = entry
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.source)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(Self.dateTimeFormatter.string(from: entry.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f drinks", entry.standardDrinks))
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(alcoholAmber)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    let entriesToDelete = indexSet.compactMap { idx -> LoopInsightsAlcoholEntry? in
                        guard idx < tracker.entries.count else { return nil }
                        return tracker.entries[idx]
                    }
                    for entry in entriesToDelete {
                        tracker.removeEntry(entry)
                    }
                }
            }
        }
    }

    // MARK: - Edit Sheet

    private func editEntrySheet(_ entry: LoopInsightsAlcoholEntry) -> some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Edit Entry", comment: "LoopInsights edit alcohol header"))) {
                    TextField(NSLocalizedString("Standard Drinks", comment: "LoopInsights alcohol amount"), text: $editDrinks)
                        .keyboardType(.decimalPad)
                    TextField(NSLocalizedString("Type", comment: "LoopInsights alcohol source"), text: $editSource)
                    DatePicker(
                        NSLocalizedString("Time", comment: "LoopInsights alcohol time"),
                        selection: $editTimestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section {
                    Button(action: {
                        if let drinks = Double(editDrinks), drinks > 0 {
                            tracker.updateEntry(
                                id: entry.id,
                                standardDrinks: drinks,
                                source: editSource.isEmpty ? "Custom" : editSource,
                                timestamp: editTimestamp
                            )
                            editingEntry = nil
                        }
                    }) {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Save Changes", comment: "LoopInsights save alcohol edit"))
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Double(editDrinks) ?? 0 > 0 ? alcoholAmber : Color.gray)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(Double(editDrinks) ?? 0 <= 0)

                    Button(role: .destructive, action: {
                        tracker.removeEntry(entry)
                        editingEntry = nil
                    }) {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Delete Entry", comment: "LoopInsights delete alcohol entry"))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Edit Drink", comment: "LoopInsights edit alcohol title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        editingEntry = nil
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Gauge color: amber base with red for high levels
    private func gaugeColor(_ drinks: Double) -> Color {
        if drinks < 2 { return alcoholAmber }
        if drinks < 4 { return Color(red: 0.9, green: 0.5, blue: 0.1) }
        return .red
    }

    /// Risk level display text
    private func riskDisplayText(_ risk: LoopInsightsAlcoholHypoRisk) -> String {
        switch risk {
        case .none: return NSLocalizedString("None", comment: "LoopInsights alcohol risk none")
        case .low: return NSLocalizedString("Low", comment: "LoopInsights alcohol risk low")
        case .moderate: return NSLocalizedString("Moderate", comment: "LoopInsights alcohol risk moderate")
        case .high: return NSLocalizedString("High", comment: "LoopInsights alcohol risk high")
        }
    }

    /// Risk level color
    private func riskColor(_ risk: LoopInsightsAlcoholHypoRisk) -> Color {
        switch risk {
        case .none: return .green
        case .low: return .yellow
        case .moderate: return .orange
        case .high: return .red
        }
    }

    /// Risk banner title
    private func riskBannerTitle(_ risk: LoopInsightsAlcoholHypoRisk) -> String {
        switch risk {
        case .none: return ""
        case .low: return NSLocalizedString("Low Hypoglycemia Risk", comment: "LoopInsights alcohol low risk title")
        case .moderate: return NSLocalizedString("Moderate Hypoglycemia Risk", comment: "LoopInsights alcohol moderate risk title")
        case .high: return NSLocalizedString("High Hypoglycemia Risk", comment: "LoopInsights alcohol high risk title")
        }
    }

    /// Risk banner detail text
    private func riskBannerDetail(_ state: LoopInsightsAlcoholState) -> String {
        var detail = NSLocalizedString("Alcohol suppresses liver glucose production, causing delayed low blood sugar 4-24 hours after drinking.", comment: "LoopInsights alcohol risk description")
        if let riskEnd = state.hypoRiskWindowEnd {
            detail += " " + String(format: NSLocalizedString("Risk window until %@.", comment: "LoopInsights alcohol risk window"), Self.timeFormatter.string(from: riskEnd))
        }
        if state.hypoRiskLevel == .high {
            detail += " " + NSLocalizedString("Monitor glucose closely, especially overnight.", comment: "LoopInsights alcohol high risk warning")
        }
        return detail
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
