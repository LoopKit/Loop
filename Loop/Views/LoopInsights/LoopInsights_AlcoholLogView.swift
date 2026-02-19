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

/// Info tips shown via (i) buttons in the alcohol tracker UI.
private enum AlcoholInfoTip: String, Identifiable {
    case estimatedLevel
    case todaysPeak
    case hypoRisk
    case estClear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .estimatedLevel:
            return NSLocalizedString("Estimated Alcohol Level", comment: "AlcoholInfoTip estimated level title")
        case .todaysPeak:
            return NSLocalizedString("Today's Peak", comment: "AlcoholInfoTip today peak title")
        case .hypoRisk:
            return NSLocalizedString("Hypo Risk", comment: "AlcoholInfoTip hypo risk title")
        case .estClear:
            return NSLocalizedString("Estimated Clear Time", comment: "AlcoholInfoTip est clear title")
        }
    }

    var message: String {
        switch self {
        case .estimatedLevel:
            return NSLocalizedString("The number of standard drinks estimated to still be in your system. Your liver metabolizes about 1 standard drink per hour. This number decreases over time as your body processes the alcohol.", comment: "AlcoholInfoTip estimated level message")
        case .todaysPeak:
            return NSLocalizedString("The highest alcohol level your body reached today. This is the most drinks in your system at any one time, which matters more for impairment and hypo risk than total drinks consumed.", comment: "AlcoholInfoTip today peak message")
        case .hypoRisk:
            return NSLocalizedString("Alcohol suppresses your liver's ability to produce glucose, which can cause delayed low blood sugar 4–24 hours after drinking. Risk is highest 8–12 hours after your last drink. The level is based on how much you drank and when.", comment: "AlcoholInfoTip hypo risk message")
        case .estClear:
            return NSLocalizedString("The estimated time when all alcohol will be metabolized from your system, based on a rate of about 1 standard drink per hour. Hypo risk may persist for hours after this time.", comment: "AlcoholInfoTip est clear message")
        }
    }
}

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
    @State private var activeInfo: AlcoholInfoTip?
    @State private var showingClearConfirmation = false
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
                        .stroke(gaugeColor(currentState.currentAlcoholLevel).opacity(0.2), lineWidth: 8)
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

                infoLabel(NSLocalizedString("Estimated Alcohol Level", comment: "LoopInsights alcohol level label"), tip: .estimatedLevel)

                if currentState.entriesLast24h > 0 {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", currentState.peakLevelToday))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(alcoholAmber)
                            infoLabel(NSLocalizedString("Today's Peak", comment: "LoopInsights alcohol today peak"), tip: .todaysPeak)
                        }
                        VStack(spacing: 2) {
                            Text(riskDisplayText(currentState.hypoRiskLevel))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(riskColor(currentState.hypoRiskLevel))
                            infoLabel(NSLocalizedString("Hypo Risk", comment: "LoopInsights alcohol hypo risk"), tip: .hypoRisk)
                        }
                        if let clearTime = currentState.estimatedClearTime {
                            VStack(spacing: 2) {
                                Text(Self.timeFormatter.string(from: clearTime))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(alcoholAmber)
                                infoLabel(NSLocalizedString("Est. Clear", comment: "LoopInsights alcohol est clear"), tip: .estClear)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .alert(item: $activeInfo) { tip in
                Alert(
                    title: Text(tip.title),
                    message: Text(tip.message),
                    dismissButton: .default(Text(NSLocalizedString("OK", comment: "OK button")))
                )
            }
        }
    }

    private func infoLabel(_ text: String, tip: AlcoholInfoTip) -> some View {
        Button(action: { activeInfo = tip }) {
            HStack(spacing: 3) {
                Text(text)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
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
                            Text(preset.icon)
                                .font(.caption)
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

                Button(role: .destructive, action: {
                    showingClearConfirmation = true
                }) {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Clear All Entries", comment: "LoopInsights clear all alcohol entries"))
                        Spacer()
                    }
                }
                .alert(NSLocalizedString("Clear All Entries?", comment: "LoopInsights clear all alcohol alert title"), isPresented: $showingClearConfirmation) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                    Button(NSLocalizedString("Clear All", comment: "LoopInsights clear all confirm"), role: .destructive) {
                        tracker.clearAllEntries()
                    }
                } message: {
                    Text(NSLocalizedString("This will remove all alcohol entries. This cannot be undone.", comment: "LoopInsights clear all alcohol alert message"))
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

    /// Gauge color: green → yellow → orange → red → dark red
    private func gaugeColor(_ drinks: Double) -> Color {
        if drinks <= 0 { return .green }
        if drinks < 1 { return .green }
        if drinks < 2 { return .yellow }
        if drinks < 3 { return .orange }
        if drinks < 4 { return .red }
        return Color(red: 0.7, green: 0.0, blue: 0.0) // dark red
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
