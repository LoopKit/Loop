//
//  LoopInsights_CaffeineLogView.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Brand color for all caffeine UI
private let caffeineGreen = Color.green

/// Info tips shown via (i) buttons in the caffeine tracker UI.
private enum CaffeineInfoTip: String, Identifiable {
    case estimatedLevel
    case totalLast24h
    case todaysPeak
    case lastIntake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .estimatedLevel:
            return NSLocalizedString("Estimated Caffeine Level", comment: "CaffeineInfoTip estimated level title")
        case .totalLast24h:
            return NSLocalizedString("24h Total", comment: "CaffeineInfoTip 24h total title")
        case .todaysPeak:
            return NSLocalizedString("Today's Peak", comment: "CaffeineInfoTip today peak title")
        case .lastIntake:
            return NSLocalizedString("Last Intake", comment: "CaffeineInfoTip last intake title")
        }
    }

    var message: String {
        switch self {
        case .estimatedLevel:
            return NSLocalizedString("The estimated milligrams of caffeine currently in your system. Caffeine has a half-life of about 5.7 hours, meaning half of what you consume is eliminated roughly every 6 hours.", comment: "CaffeineInfoTip estimated level message")
        case .totalLast24h:
            return NSLocalizedString("The total milligrams of caffeine consumed in the last 24 hours from all sources. The FDA considers 400 mg/day a safe amount for most adults.", comment: "CaffeineInfoTip 24h total message")
        case .todaysPeak:
            return NSLocalizedString("The highest caffeine level your body reached today. High peak levels can amplify effects on blood sugar, heart rate, and sleep quality.", comment: "CaffeineInfoTip today peak message")
        case .lastIntake:
            return NSLocalizedString("When you last consumed caffeine. Caffeine consumed within 6 hours of bedtime can disrupt sleep and affect overnight glucose control.", comment: "CaffeineInfoTip last intake message")
        }
    }
}

/// Caffeine logging UI: shows current level gauge, quick-add presets, and entry log.
struct LoopInsights_CaffeineLogView: View {

    @ObservedObject var tracker: LoopInsights_CaffeineTracker
    @State private var customMg: String = ""
    @State private var customSource: String = ""
    @State private var showingCustomEntry = false
    @State private var editingEntry: LoopInsightsCaffeineEntry?
    @State private var editMg: String = ""
    @State private var editSource: String = ""
    @State private var editTimestamp: Date = Date()
    @State private var showingClearConfirmation = false
    @State private var activeInfo: CaffeineInfoTip?
    @Environment(\.dismiss) private var dismiss

    private var currentState: LoopInsightsCaffeineState {
        tracker.currentState()
    }

    var body: some View {
        List {
            currentLevelSection
            quickAddSection
            if showingCustomEntry {
                customEntrySection
            }
            recentEntriesSection
        }
        .navigationTitle(NSLocalizedString("Caffeine Tracker", comment: "LoopInsights caffeine title"))
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
        .task {
            await tracker.syncFromHealthKit()
        }
    }

    // MARK: - Current Level

    private var currentLevelSection: some View {
        Section {
            VStack(spacing: 12) {
                // Level gauge
                ZStack {
                    Circle()
                        .stroke(gaugeColor(currentState.currentLevelMg).opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)

                    let level = min(currentState.currentLevelMg, 400)
                    Circle()
                        .trim(from: 0, to: level / 400)
                        .stroke(gaugeColor(level), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", currentState.currentLevelMg))
                            .font(.title2.weight(.bold))
                            .foregroundColor(gaugeColor(currentState.currentLevelMg))
                        Text("mg")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                infoLabel(NSLocalizedString("Estimated Caffeine Level", comment: "LoopInsights caffeine level label"), tip: .estimatedLevel)

                if currentState.entriesLast24h > 0 {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f mg", currentState.totalMgLast24h))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(caffeineGreen)
                            infoLabel(NSLocalizedString("24h Total", comment: "LoopInsights caffeine 24h total"), tip: .totalLast24h)
                        }
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f mg", currentState.peakLevelToday))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(caffeineGreen)
                            infoLabel(NSLocalizedString("Today's Peak", comment: "LoopInsights caffeine today peak"), tip: .todaysPeak)
                        }
                        if let lastTime = currentState.lastIntakeTime {
                            VStack(spacing: 2) {
                                Text(Self.timeFormatter.string(from: lastTime))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(caffeineGreen)
                                infoLabel(NSLocalizedString("Last Intake", comment: "LoopInsights caffeine last intake"), tip: .lastIntake)
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

    private func infoLabel(_ text: String, tip: CaffeineInfoTip) -> some View {
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

    // MARK: - Quick Add

    private var quickAddSection: some View {
        Section(header: Text(NSLocalizedString("Quick Add", comment: "LoopInsights caffeine quick add header"))) {
            let presets = LoopInsightsCaffeinePreset.defaults
            let columns = [GridItem(.flexible()), GridItem(.flexible())]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(presets) { preset in
                    Button(action: {
                        tracker.logCaffeine(milligrams: preset.milligrams, source: preset.name)
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
                                Text(String(format: "%.0f mg", preset.milligrams))
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
                    Text(NSLocalizedString("Custom Entry", comment: "LoopInsights caffeine custom entry"))
                }
                .font(.subheadline)
                .foregroundColor(caffeineGreen)
            }
        }
    }

    // MARK: - Custom Entry

    private var customEntrySection: some View {
        Section(header: Text(NSLocalizedString("Custom Caffeine Entry", comment: "LoopInsights custom caffeine header"))) {
            TextField(NSLocalizedString("Amount (mg)", comment: "LoopInsights caffeine amount placeholder"), text: $customMg)
                .keyboardType(.decimalPad)
            TextField(NSLocalizedString("Source (e.g. Matcha Latte)", comment: "LoopInsights caffeine source placeholder"), text: $customSource)

            Button(action: {
                if let mg = Double(customMg), mg > 0 {
                    let source = customSource.isEmpty ? "Custom" : customSource
                    tracker.logCaffeine(milligrams: mg, source: source)
                    customMg = ""
                    customSource = ""
                    showingCustomEntry = false
                }
            }) {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("Add Entry", comment: "LoopInsights caffeine add entry"))
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .background(Double(customMg) ?? 0 > 0 ? caffeineGreen : Color.gray)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(Double(customMg) ?? 0 <= 0)
        }
    }

    // MARK: - Recent Entries

    private var recentEntriesSection: some View {
        Section(header: Text(NSLocalizedString("Recent Entries", comment: "LoopInsights caffeine recent entries"))) {
            if tracker.entries.isEmpty {
                Text(NSLocalizedString("No caffeine entries yet. Tap a preset above to log intake.", comment: "LoopInsights no caffeine entries"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(tracker.entries.prefix(20)) { entry in
                    Button(action: {
                        if !entry.isFromHealthKit {
                            editMg = String(format: "%.0f", entry.milligrams)
                            editSource = entry.source
                            editTimestamp = entry.timestamp
                            editingEntry = entry
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(entry.source)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    if entry.isFromHealthKit {
                                        Image(systemName: "heart.fill")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                                Text(Self.dateTimeFormatter.string(from: entry.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.0f mg", entry.milligrams))
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(caffeineGreen)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    let entriesToDelete = indexSet.compactMap { idx -> LoopInsightsCaffeineEntry? in
                        guard idx < tracker.entries.count else { return nil }
                        let entry = tracker.entries[idx]
                        return entry.isFromHealthKit ? nil : entry
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
                        Text(NSLocalizedString("Clear All Entries", comment: "LoopInsights clear all caffeine entries"))
                        Spacer()
                    }
                }
                .alert(NSLocalizedString("Clear All Entries?", comment: "LoopInsights clear all caffeine alert title"), isPresented: $showingClearConfirmation) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
                    Button(NSLocalizedString("Clear All", comment: "LoopInsights clear all confirm"), role: .destructive) {
                        tracker.clearAllEntries()
                    }
                } message: {
                    Text(NSLocalizedString("This will remove all manual caffeine entries. HealthKit entries will remain. This cannot be undone.", comment: "LoopInsights clear all caffeine alert message"))
                }
            }
        }
    }

    // MARK: - Edit Sheet

    private func editEntrySheet(_ entry: LoopInsightsCaffeineEntry) -> some View {
        NavigationView {
            Form {
                Section(header: Text(NSLocalizedString("Edit Entry", comment: "LoopInsights edit caffeine header"))) {
                    TextField(NSLocalizedString("Amount (mg)", comment: "LoopInsights caffeine amount"), text: $editMg)
                        .keyboardType(.decimalPad)
                    TextField(NSLocalizedString("Source", comment: "LoopInsights caffeine source"), text: $editSource)
                    DatePicker(
                        NSLocalizedString("Time", comment: "LoopInsights caffeine time"),
                        selection: $editTimestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section {
                    Button(action: {
                        if let mg = Double(editMg), mg > 0 {
                            tracker.updateEntry(
                                id: entry.id,
                                milligrams: mg,
                                source: editSource.isEmpty ? "Custom" : editSource,
                                timestamp: editTimestamp
                            )
                            editingEntry = nil
                        }
                    }) {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Save Changes", comment: "LoopInsights save caffeine edit"))
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Double(editMg) ?? 0 > 0 ? caffeineGreen : Color.gray)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(Double(editMg) ?? 0 <= 0)

                    Button(role: .destructive, action: {
                        tracker.removeEntry(entry)
                        editingEntry = nil
                    }) {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Delete Entry", comment: "LoopInsights delete caffeine entry"))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Edit Caffeine", comment: "LoopInsights edit caffeine title"))
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
    private func gaugeColor(_ mg: Double) -> Color {
        if mg <= 0 { return .green }
        if mg < 100 { return .green }
        if mg < 200 { return .yellow }
        if mg < 300 { return .orange }
        if mg < 400 { return .red }
        return Color(red: 0.7, green: 0.0, blue: 0.0) // dark red
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
