//
//  DataLayer_DashboardView.swift
//  Loop
//
//  DataLayer — Local data visualization dashboard.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftUI

/// Dashboard showing locally recorded DataLayer events with
/// visual breakdowns by type, upload status, and daily volume.
struct DataLayer_DashboardView: View {

    @State private var eventsByType: [(String, Int)] = []
    @State private var uploadStatus: [(String, Int)] = []
    @State private var dailyCounts: [(String, Int)] = []
    @State private var recentEvents: [DataLayer_Event] = []
    @State private var totalEvents = 0

    private let store = DataLayer_EventCollector.shared.eventStore

    var body: some View {
        List {
            summarySection
            dailyTrendSection
            eventsByTypeSection
            uploadStatusSection
            recentEventsSection
        }
        .navigationTitle("DataLayer Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadData() }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.blue)
                    Text("OVERVIEW")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                HStack {
                    statCard(value: "\(totalEvents)", label: "Total Events", color: .blue)
                    statCard(value: "\(eventsByType.count)", label: "Event Types", color: .purple)
                    statCard(value: "\(uploadedCount)", label: "Uploaded", color: .green)
                    statCard(value: "\(pendingCount)", label: "Pending", color: .orange)
                }
            }
        }
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Daily Trend

    private var dailyTrendSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("DAILY VOLUME (14 DAYS)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                if dailyCounts.isEmpty {
                    Text("No data yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    let maxCount = dailyCounts.map(\.1).max() ?? 1
                    ForEach(dailyCounts, id: \.0) { day, count in
                        HStack(spacing: 8) {
                            Text(shortDate(day))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .trailing)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
                            }
                            .frame(height: 14)

                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 35, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Events by Type

    private var eventsByTypeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(.purple)
                    Text("EVENTS BY TYPE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                if eventsByType.isEmpty {
                    Text("No events recorded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    let maxCount = eventsByType.first?.1 ?? 1
                    ForEach(eventsByType, id: \.0) { type, count in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: iconForEventType(type))
                                    .foregroundColor(colorForEventType(type))
                                    .frame(width: 16)
                                Text(displayName(for: type))
                                    .font(.caption)
                                Spacer()
                                Text("\(count)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorForEventType(type).opacity(0.4))
                                    .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Upload Status

    private var uploadStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundColor(.green)
                    Text("UPLOAD STATUS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                if totalEvents == 0 {
                    Text("No events to upload")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    // Stacked bar
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            ForEach(uploadStatus, id: \.0) { status, count in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(colorForStatus(status))
                                    .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(totalEvents)))
                            }
                        }
                    }
                    .frame(height: 20)

                    // Legend
                    HStack(spacing: 16) {
                        ForEach(uploadStatus, id: \.0) { status, count in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForStatus(status))
                                    .frame(width: 8, height: 8)
                                Text("\(status): \(count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Events

    private var recentEventsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.blue)
                    Text("RECENT EVENTS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }

                if recentEvents.isEmpty {
                    Text("No events yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recentEvents, id: \.id) { event in
                        HStack {
                            Image(systemName: iconForEventType(event.eventType.rawValue))
                                .foregroundColor(colorForEventType(event.eventType.rawValue))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: event.eventType.rawValue))
                                    .font(.caption)
                                Text(event.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            statusBadge(event.uploadStatus.rawValue)
                        }
                        if event.id != recentEvents.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colorForStatus(status).opacity(0.15))
            .foregroundColor(colorForStatus(status))
            .cornerRadius(4)
    }

    // MARK: - Data Loading

    private func loadData() {
        totalEvents = store.eventCount()
        eventsByType = store.eventCountsByType()
        uploadStatus = store.uploadStatusCounts()
        dailyCounts = store.dailyEventCounts(days: 14)
        recentEvents = store.recentEvents(limit: 25)
    }

    // MARK: - Computed

    private var uploadedCount: Int {
        uploadStatus.first(where: { $0.0 == "uploaded" })?.1 ?? 0
    }

    private var pendingCount: Int {
        uploadStatus.first(where: { $0.0 == "pending" })?.1 ?? 0
    }

    // MARK: - Helpers

    private func shortDate(_ dateStr: String) -> String {
        // "2026-03-01" → "Mar 1"
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return month < months.count ? "\(months[month]) \(day)" : dateStr
    }

    private func displayName(for type: String) -> String {
        switch type {
        case "glucoseSample": return "Glucose"
        case "insulinDelivery": return "Insulin"
        case "carbEntry": return "Carbs"
        case "mealAnalysis": return "Meal Analysis"
        case "mealConfirmed": return "Meal Confirmed"
        case "barcodeScanned": return "Barcode Scan"
        case "aiSuggestionGenerated": return "AI Generated"
        case "aiSuggestionApplied": return "AI Applied"
        case "aiSuggestionDismissed": return "AI Dismissed"
        case "aiSuggestionReverted": return "AI Reverted"
        case "chatMessage": return "Chat"
        case "backgroundAlert": return "Alert"
        case "mealDebrief": return "Meal Debrief"
        case "caffeineLogged": return "Caffeine"
        case "alcoholLogged": return "Alcohol"
        case "presetActivated": return "Preset On"
        case "presetDeactivated": return "Preset Off"
        case "activityDetected": return "Activity"
        case "biometricSnapshot": return "Biometrics"
        case "therapySettingsChanged": return "Settings Change"
        case "overrideActivated": return "Override On"
        case "overrideDeactivated": return "Override Off"
        case "sessionStart": return "Session Start"
        case "sessionEnd": return "Session End"
        default: return type
        }
    }

    private func iconForEventType(_ type: String) -> String {
        switch type {
        case "glucoseSample": return "drop.fill"
        case "insulinDelivery": return "syringe.fill"
        case "carbEntry", "mealAnalysis", "mealConfirmed", "mealDebrief": return "fork.knife"
        case "barcodeScanned": return "barcode.viewfinder"
        case "aiSuggestionGenerated", "aiSuggestionApplied", "aiSuggestionDismissed", "aiSuggestionReverted": return "brain.head.profile"
        case "chatMessage": return "bubble.left.fill"
        case "backgroundAlert": return "bell.fill"
        case "caffeineLogged": return "cup.and.saucer.fill"
        case "alcoholLogged": return "wineglass.fill"
        case "presetActivated", "presetDeactivated", "activityDetected": return "figure.run"
        case "biometricSnapshot": return "heart.fill"
        case "therapySettingsChanged": return "gearshape.fill"
        case "overrideActivated", "overrideDeactivated": return "bolt.fill"
        case "sessionStart", "sessionEnd": return "power"
        default: return "circle.fill"
        }
    }

    private func colorForEventType(_ type: String) -> Color {
        switch type {
        case "glucoseSample": return .red
        case "insulinDelivery": return .orange
        case "carbEntry", "mealAnalysis", "mealConfirmed", "mealDebrief", "barcodeScanned": return Color(red: 107/255, green: 47/255, blue: 160/255)
        case "aiSuggestionGenerated", "aiSuggestionApplied", "aiSuggestionDismissed", "aiSuggestionReverted", "chatMessage", "backgroundAlert": return Color(red: 26/255, green: 138/255, blue: 158/255)
        case "caffeineLogged": return .brown
        case "alcoholLogged": return Color(red: 0.9, green: 0.6, blue: 0.1)
        case "presetActivated", "presetDeactivated", "activityDetected": return Color(red: 76/255, green: 175/255, blue: 80/255)
        case "biometricSnapshot": return .pink
        case "therapySettingsChanged": return .gray
        case "overrideActivated", "overrideDeactivated": return .yellow
        case "sessionStart", "sessionEnd": return .secondary
        default: return .blue
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "pending": return .orange
        case "uploading": return .blue
        case "uploaded": return .green
        case "failed": return .red
        case "redacted": return .gray
        default: return .secondary
        }
    }
}
