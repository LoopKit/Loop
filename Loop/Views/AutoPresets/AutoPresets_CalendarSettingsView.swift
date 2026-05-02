//
//  AutoPresets_CalendarSettingsView.swift
//  Loop
//
//  AutoPresets — Settings UI for calendar-based preset activation.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import EventKit
import LoopKit
import SwiftUI

// MARK: - Main Calendar Settings View

struct AutoPresets_CalendarSettingsView: View {
    @ObservedObject private var calendarManager = AutoPresets_CalendarManager.shared
    @ObservedObject private var coordinator = AutoPresets_Coordinator.shared
    @State private var showingAddTrigger = false

    var body: some View {
        List {
            enableSection
            if calendarManager.isEnabled {
                authorizationSection
                triggersSection
                leadTimeSection
                upcomingSection
                calendarFilterSection
                infoSection
            }
        }
        .navigationTitle("Calendar Triggers")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddTrigger) {
            NavigationView {
                AutoPresets_CalendarTriggerEditView(
                    trigger: nil,
                    availablePresets: coordinator.availablePresets()
                )
            }
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { calendarManager.isEnabled },
                set: { calendarManager.isEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar Triggers")
                        .font(.headline)
                    Text("Automatically activate presets before calendar events that match your keywords.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Authorization Section

    @ViewBuilder
    private var authorizationSection: some View {
        if !calendarManager.hasAuthorization {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundColor(.orange)
                        Text("Calendar Access Required")
                            .font(.headline)
                    }

                    if calendarManager.authorizationStatus == .notDetermined {
                        Text("AutoPresets needs calendar access to scan for events matching your keywords.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Allow Calendar Access") {
                            calendarManager.requestAuthorization()
                        }
                        .font(.body.weight(.medium))
                    } else {
                        Text("Calendar access was denied. Go to Settings → Loop → Calendars to enable it.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.body.weight(.medium))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Triggers Section

    private var triggersSection: some View {
        Section {
            if calendarManager.triggers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No keywords saved")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Add keywords that match your calendar events (e.g. \"Gym\", \"Spin Class\", \"Run\").")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(calendarManager.triggers) { trigger in
                    NavigationLink {
                        AutoPresets_CalendarTriggerEditView(
                            trigger: trigger,
                            availablePresets: coordinator.availablePresets()
                        )
                    } label: {
                        triggerRow(trigger)
                    }
                }
                .onDelete { offsets in
                    calendarManager.removeTriggers(at: offsets)
                }
            }

            Button {
                showingAddTrigger = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                    Text("Add Keyword")
                        .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                }
            }
            .disabled(!calendarManager.hasAuthorization)
        } header: {
            Text("Keywords")
        } footer: {
            Text("Events are matched by title containing the keyword (case-insensitive).")
        }
    }

    // MARK: - Lead Time Section

    private var leadTimeSection: some View {
        Section("Timing") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Activate Before Event")
                        .font(.headline)
                    Spacer()
                    Text(formatLeadTime(calendarManager.leadTimeMinutes))
                        .foregroundColor(.secondary)
                }

                Picker("Lead Time", selection: Binding(
                    get: { calendarManager.leadTimeMinutes },
                    set: { calendarManager.leadTimeMinutes = $0 }
                )) {
                    Text("At event start").tag(0)
                    Text("5 min before").tag(5)
                    Text("10 min before").tag(10)
                    Text("15 min before").tag(15)
                    Text("30 min before").tag(30)
                    Text("1 hour before").tag(60)
                }
                .pickerStyle(.menu)

                Text("How early to activate the preset before the calendar event starts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: Binding(
                get: { calendarManager.deactivateOnEventEnd },
                set: { calendarManager.deactivateOnEventEnd = $0 }
            )) {
                VStack(alignment: .leading) {
                    Text("Deactivate When Event Ends")
                        .font(.headline)
                    Text("Automatically remove the preset when the calendar event ends.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Upcoming Matches Section

    @ViewBuilder
    private var upcomingSection: some View {
        if !calendarManager.upcomingMatches.isEmpty {
            Section("Upcoming") {
                ForEach(calendarManager.upcomingMatches) { match in
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title3)
                            .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.eventTitle)
                                .font(.body.weight(.medium))

                            HStack(spacing: 4) {
                                Text(formatEventTime(match.eventStart))
                                    .font(.caption)
                                if let preset = coordinator.availablePresets().first(where: { $0.id.uuidString == match.trigger.presetId }) {
                                    Text("→ \(preset.symbol) \(preset.name)")
                                        .font(.caption)
                                }
                            }
                            .foregroundColor(.secondary)

                            if match.activationDate > Date() {
                                Text("Activates \(Self.relativeFormatter.localizedString(for: match.activationDate, relativeTo: Date()))")
                                    .font(.caption2)
                                    .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                            } else {
                                Text("Active now")
                                    .font(.caption2)
                                    .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
        }

        Section {
            Button {
                calendarManager.rescan()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan Calendar Now")
                }
            }
            .disabled(!calendarManager.hasAuthorization)
        }
    }

    // MARK: - Calendar Filter Section

    @ViewBuilder
    private var calendarFilterSection: some View {
        if calendarManager.hasAuthorization {
            Section {
                let calendars = calendarManager.availableCalendars()

                if calendarManager.enabledCalendarIDs.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                        Text("Watching all calendars")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    Button {
                        calendarManager.toggleCalendar(calendar)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 12, height: 12)
                            Text(calendar.title)
                                .foregroundColor(.primary)
                            Spacer()
                            if calendarManager.isCalendarEnabled(calendar) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !calendarManager.enabledCalendarIDs.isEmpty {
                    Button("Watch All Calendars") {
                        calendarManager.watchAllCalendars()
                    }
                    .font(.caption)
                }
            } header: {
                Text("Calendars to Watch")
            } footer: {
                Text("Only events from selected calendars will be matched. By default, all calendars are watched.")
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("How it works", systemImage: "info.circle")
                    .font(.subheadline.weight(.medium))
                Text("AutoPresets scans your calendar every 15 minutes for events in the next 24 hours. When an event title matches one of your keywords, the assigned preset activates at your configured lead time. Works with all calendar providers (iCloud, Google, Outlook, Exchange).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Label("Safety", systemImage: "shield.checkmark")
                    .font(.subheadline.weight(.medium))
                Text("A calendar trigger will never override a preset you've manually activated. All activations appear in the AutoPresets activity log.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Row Helpers

    private func triggerRow(_ trigger: AutoPresetsCalendarTrigger) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundColor(trigger.isEnabled ? Color(red: 76/255, green: 175/255, blue: 80/255) : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("\"\(trigger.keyword)\"")
                    .font(.body.weight(.medium))

                if let preset = coordinator.availablePresets().first(where: { $0.id.uuidString == trigger.presetId }) {
                    Text("→ \(preset.symbol) \(preset.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No preset assigned")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            if !trigger.isEnabled {
                Text("Off")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Formatters

    private func formatLeadTime(_ minutes: Int) -> String {
        if minutes == 0 { return "At start" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hour"
    }

    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today' h:mm a"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow' h:mm a"
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    private static var relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        return f
    }()
}

// MARK: - Trigger Edit View

struct AutoPresets_CalendarTriggerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var calendarManager = AutoPresets_CalendarManager.shared

    @State private var keyword: String
    @State private var selectedPresetId: String
    @State private var isEnabled: Bool
    @State private var showingDeleteConfirm = false

    private let existingTrigger: AutoPresetsCalendarTrigger?
    private let availablePresets: [TemporaryScheduleOverridePreset]
    private var isEditing: Bool { existingTrigger != nil }

    init(trigger: AutoPresetsCalendarTrigger?, availablePresets: [TemporaryScheduleOverridePreset]) {
        self.existingTrigger = trigger
        self.availablePresets = availablePresets

        _keyword = State(initialValue: trigger?.keyword ?? "")
        _selectedPresetId = State(initialValue: trigger?.presetId ?? "")
        _isEnabled = State(initialValue: trigger?.isEnabled ?? true)
    }

    var body: some View {
        Form {
            keywordSection
            presetSection
            if isEditing {
                enableSection
                deleteSection
            }
        }
        .navigationTitle(isEditing ? "Edit Keyword" : "Add Keyword")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !isEditing {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    saveTrigger()
                }
                .disabled(!canSave)
            }
        }
    }

    private var keywordSection: some View {
        Section {
            TextField("e.g. Gym, Spin Class, Run, Yoga", text: $keyword)
                .autocapitalization(.words)
        } header: {
            Text("Keyword")
        } footer: {
            Text("Events whose title contains this keyword will trigger the preset. Matching is case-insensitive.")
        }
    }

    private var presetSection: some View {
        Section("Preset to Activate") {
            if availablePresets.isEmpty {
                Text("No presets available. Create presets in Loop settings first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(availablePresets, id: \.id) { preset in
                    Button {
                        selectedPresetId = preset.id.uuidString
                    } label: {
                        HStack {
                            Text("\(preset.symbol) \(preset.name)")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedPresetId == preset.id.uuidString {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var enableSection: some View {
        Section {
            Toggle("Keyword Enabled", isOn: $isEnabled)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete Keyword")
                    Spacer()
                }
            }
            .alert("Delete Keyword?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let existing = existingTrigger {
                        calendarManager.removeTrigger(existing)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will stop matching events for \"\(keyword)\".")
            }
        }
    }

    private var canSave: Bool {
        !keyword.trimmingCharacters(in: .whitespaces).isEmpty && !selectedPresetId.isEmpty
    }

    private func saveTrigger() {
        let trigger = AutoPresetsCalendarTrigger(
            id: existingTrigger?.id ?? UUID(),
            keyword: keyword.trimmingCharacters(in: .whitespaces),
            presetId: selectedPresetId,
            isEnabled: isEnabled
        )

        if isEditing {
            calendarManager.updateTrigger(trigger)
        } else {
            calendarManager.addTrigger(trigger)
        }
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
struct AutoPresets_CalendarSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AutoPresets_CalendarSettingsView()
        }
    }
}
#endif
