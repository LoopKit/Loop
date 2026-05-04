//
//  SiteAtlas_SettingsView.swift
//  Loop
//
//  SiteAtlas — Settings and history view for site rotation tracking.
//  Shows body map overview, history list grouped by month, and management options.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct SiteAtlas_SettingsView: View {

    @ObservedObject private var coordinator = SiteAtlas_Coordinator.shared
    @State private var entries: [SiteAtlas_SiteEntry] = []
    @State private var selectedTab = 0
    @State private var selectedSide: SiteAtlas_BodySide = .front
    @State private var showDeleteConfirmation = false
    @State private var showSiteSelectionSheet = false
    @State private var editingEntry: SiteAtlas_SiteEntry? = nil
    @State private var zoneToggleCount = 0
    @State private var featureEnabled = SiteAtlas_FeatureFlags.isEnabled

    var body: some View {
        List {
            featureToggleSection
            if featureEnabled {
                nextUpSection
                quickActionsSection
                mapOverviewSection
                zoneManagementSection
                historySection
                if !hiddenEntries.isEmpty {
                    hiddenSection
                }
                dangerZoneSection
            }
        }
        .navigationTitle("Site Atlas")
        .onAppear { entries = coordinator.allEntries() }
        .sheet(isPresented: $showSiteSelectionSheet, onDismiss: refreshEntries) {
            SiteAtlas_SiteSelectionSheet()
        }
        .sheet(isPresented: $coordinator.pendingSiteLog, onDismiss: refreshEntries) {
            SiteAtlas_SiteSelectionSheet()
        }
        .sheet(item: $editingEntry, onDismiss: refreshEntries) { entry in
            SiteAtlas_EditEntrySheet(entry: entry, coordinator: coordinator)
        }
        .alert("Delete All Sites", isPresented: $showDeleteConfirmation) {
            Button("Delete All", role: .destructive) {
                coordinator.deleteAllEntries()
                refreshEntries()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all \(entries.count) site entries. This cannot be undone.")
        }
    }

    // MARK: - Sections

    private var featureToggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { featureEnabled },
                set: {
                    SiteAtlas_FeatureFlags.isEnabled = $0
                    featureEnabled = $0
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Site Atlas")
                        .font(.body)
                    Text("Track pump and sensor site rotation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(SiteAtlas_Theme.primaryColor)
        }
    }

    private var quickActionsSection: some View {
        Section("Log New Site") {
            Button {
                coordinator.promptManualLog(type: .pump)
                showSiteSelectionSheet = true
            } label: {
                Label("Log Pump Site", systemImage: "cross.circle.fill")
                    .foregroundColor(SiteAtlas_Theme.primaryColor)
            }

            Button {
                coordinator.promptManualLog(type: .sensor)
                showSiteSelectionSheet = true
            } label: {
                Label("Log Sensor Site", systemImage: "sensor.fill")
                    .foregroundColor(SiteAtlas_Theme.sensorColor)
            }

            // Last site info
            if let lastPump = coordinator.mostRecent(ofType: .pump) {
                lastSiteRow(entry: lastPump, label: "Last Pump Site")
            }
            if let lastSensor = coordinator.mostRecent(ofType: .sensor) {
                lastSiteRow(entry: lastSensor, label: "Last Sensor")
            }
        }
    }

    private var mapOverviewSection: some View {
        Section("Body Map") {
            VStack(spacing: 8) {
                SiteAtlas_SwipeableBodyMap(
                    entries: entries,
                    interactive: false,
                    selectedSide: $selectedSide,
                    onPinMoved: { id, newPoint in
                        movePin(id: id, to: newPoint)
                    }
                )
                .frame(height: 608)
                .id(zoneToggleCount)

                SiteAtlas_MapLegend()

                Text("Drag any pin to adjust its position")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var zoneManagementSection: some View {
        Section {
            DisclosureGroup {
                ForEach(SiteAtlas_Zones.all) { zone in
                    Toggle(isOn: Binding(
                        get: { SiteAtlas_Zones.isEnabled(zone) },
                        set: { _ in
                            SiteAtlas_Zones.toggleZone(zone)
                            zoneToggleCount += 1
                        }
                    )) {
                        HStack(spacing: 10) {
                            Ellipse()
                                .fill(Color.gray.opacity(0.25))
                                .overlay(Ellipse().strokeBorder(Color.gray.opacity(0.5), lineWidth: 1))
                                .frame(width: 20, height: 14)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(zone.displayName)
                                    .font(.subheadline)
                                Text(zone.bodySide.displayName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(SiteAtlas_Theme.primaryColor)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.dashed")
                        .foregroundColor(SiteAtlas_Theme.primaryColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Enable Placement Zones")
                            .font(.subheadline.weight(.medium))
                        let _ = zoneToggleCount // trigger re-render on toggle
                        let enabled = SiteAtlas_Zones.all.filter { SiteAtlas_Zones.isEnabled($0) }.count
                        Text("\(enabled) of \(SiteAtlas_Zones.all.count) zones active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } footer: {
            Text("Toggle off zones you don't use. Disabled zones are hidden from the body map.")
        }
    }

    private var nextUpSection: some View {
        Section {
            if visibleEntries.isEmpty {
                Text("Log your first site to get recommendations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(nextUpEntries.prefix(5)) { entry in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(SiteAtlas_Theme.ageColor(daysSincePlaced: entry.daysSincePlaced))
                            .frame(width: 12, height: 12)

                        Image(systemName: entry.type.iconName)
                            .font(.title3)
                            .foregroundColor(SiteAtlas_Theme.ageColor(daysSincePlaced: entry.daysSincePlaced))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.type.displayName)
                                .font(.subheadline.weight(.medium))
                            Text("\(entry.bodySide.displayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(entry.daysSincePlaced)d ago")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(SiteAtlas_Theme.ageColor(daysSincePlaced: entry.daysSincePlaced))
                            if entry.daysSincePlaced >= 3 {
                                Text("Ready")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
        } header: {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(SiteAtlas_Theme.primaryColor)
                Text("Next Up — Oldest First")
            }
        }
    }

    private var historySection: some View {
        Section("History (\(visibleEntries.count) sites)") {
            if visibleEntries.isEmpty {
                Text("No sites logged yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(groupedByMonth, id: \.key) { month, monthEntries in
                    Section(header: Text(month)) {
                        ForEach(monthEntries) { entry in
                            Button {
                                editingEntry = entry
                            } label: {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleHidden(entry)
                                } label: {
                                    Label("Hide", systemImage: "eye.slash")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    coordinator.deleteEntry(id: entry.id)
                                    refreshEntries()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var hiddenSection: some View {
        Section {
            ForEach(hiddenEntries) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.type.iconName)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.type.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(entry.bodySide.displayName) — \(entry.daysSincePlaced)d ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .swipeActions(edge: .leading) {
                    Button {
                        toggleHidden(entry)
                    } label: {
                        Label("Show", systemImage: "eye")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        coordinator.deleteEntry(id: entry.id)
                        refreshEntries()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            HStack {
                Image(systemName: "eye.slash")
                Text("Hidden (\(hiddenEntries.count))")
            }
        } footer: {
            Text("Swipe right to show again")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete All Site Data", systemImage: "trash")
            }
            .disabled(entries.isEmpty)
        }
    }

    // MARK: - Subviews

    private func lastSiteRow(entry: SiteAtlas_SiteEntry, label: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(entry.date, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("ago")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func entryRow(_ entry: SiteAtlas_SiteEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.type.iconName)
                .font(.title3)
                .foregroundColor(entry.type.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.displayName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(entry.bodySide.displayName)
                    if let notes = entry.notes, !notes.isEmpty {
                        Text("- \(notes)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text(entry.date, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Computed

    /// Entries visible on the map (not hidden).
    private var visibleEntries: [SiteAtlas_SiteEntry] {
        entries.filter { !$0.isHidden }
    }

    /// Hidden entries.
    private var hiddenEntries: [SiteAtlas_SiteEntry] {
        entries.filter { $0.isHidden }
    }

    /// Entries sorted oldest-first for "Next Up" recommendations.
    private var nextUpEntries: [SiteAtlas_SiteEntry] {
        visibleEntries.sorted { $0.date < $1.date }
    }

    private var groupedByMonth: [(key: String, value: [SiteAtlas_SiteEntry])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: visibleEntries.sorted { $0.date > $1.date }) {
            formatter.string(from: $0.date)
        }

        return grouped.sorted { $0.key > $1.key }
    }

    // MARK: - Actions

    private func refreshEntries() {
        entries = coordinator.allEntries()
    }

    private func toggleHidden(_ entry: SiteAtlas_SiteEntry) {
        var updated = entry
        updated.isHidden.toggle()
        coordinator.updateEntry(updated)
        refreshEntries()
    }

    private func movePin(id: UUID, to newPoint: CGPoint) {
        guard var entry = entries.first(where: { $0.id == id }) else { return }
        entry.normalizedX = newPoint.x
        entry.normalizedY = newPoint.y
        coordinator.updateEntry(entry)
        refreshEntries()
    }
}

// MARK: - Edit Entry Sheet

struct SiteAtlas_EditEntrySheet: View {

    let entry: SiteAtlas_SiteEntry
    let coordinator: SiteAtlas_Coordinator

    @State private var editedDate: Date
    @State private var editedType: SiteAtlas_SiteType
    @State private var editedNotes: String
    @Environment(\.dismiss) private var dismiss

    init(entry: SiteAtlas_SiteEntry, coordinator: SiteAtlas_Coordinator) {
        self.entry = entry
        self.coordinator = coordinator
        _editedDate = State(initialValue: entry.date)
        _editedType = State(initialValue: entry.type)
        _editedNotes = State(initialValue: entry.notes ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Site Type") {
                    Picker("Type", selection: $editedType) {
                        ForEach(SiteAtlas_SiteType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Date & Time") {
                    DatePicker(
                        "Site placed",
                        selection: $editedDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .tint(SiteAtlas_Theme.primaryColor)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $editedNotes)
                }

                Section("Location") {
                    HStack {
                        Text("Side")
                        Spacer()
                        Text(entry.bodySide.displayName)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Position")
                        Spacer()
                        Text(String(format: "(%.0f%%, %.0f%%)", entry.normalizedX * 100, entry.normalizedY * 100))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveChanges() }
                        .font(.headline)
                        .foregroundColor(SiteAtlas_Theme.primaryColor)
                }
            }
        }
    }

    private func saveChanges() {
        var updated = entry
        updated.date = editedDate
        updated.type = editedType
        updated.notes = editedNotes.isEmpty ? nil : editedNotes
        coordinator.updateEntry(updated)
        dismiss()
    }
}
