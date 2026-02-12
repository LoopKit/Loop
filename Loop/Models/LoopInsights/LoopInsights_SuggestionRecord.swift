//
//  LoopInsights_SuggestionRecord.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Suggestion Status

/// The lifecycle status of a suggestion
enum LoopInsightsSuggestionStatus: String, Codable {
    case pending = "pending"
    case applied = "applied"
    case dismissed = "dismissed"
    case autoApplied = "auto_applied"

    var displayName: String {
        switch self {
        case .pending:
            return NSLocalizedString("Pending", comment: "LoopInsights suggestion status: pending review")
        case .applied:
            return NSLocalizedString("Applied", comment: "LoopInsights suggestion status: user applied")
        case .dismissed:
            return NSLocalizedString("Dismissed", comment: "LoopInsights suggestion status: user dismissed")
        case .autoApplied:
            return NSLocalizedString("Auto-Applied", comment: "LoopInsights suggestion status: automatically applied")
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .applied: return "checkmark.circle.fill"
        case .dismissed: return "xmark.circle"
        case .autoApplied: return "bolt.circle.fill"
        }
    }

    var isResolved: Bool {
        switch self {
        case .pending: return false
        case .applied, .dismissed, .autoApplied: return true
        }
    }
}

// MARK: - Suggestion Record

/// A persistent record of a suggestion, including its status and any actions taken
struct LoopInsightsSuggestionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let suggestion: LoopInsightsSuggestion
    var status: LoopInsightsSuggestionStatus
    let createdAt: Date
    var resolvedAt: Date?
    var applyMode: LoopInsightsApplyMode?
    var settingsSnapshotBefore: LoopInsightsTherapySnapshot?
    var settingsSnapshotAfter: LoopInsightsTherapySnapshot?

    init(suggestion: LoopInsightsSuggestion) {
        self.id = UUID()
        self.suggestion = suggestion
        self.status = .pending
        self.createdAt = Date()
        self.resolvedAt = nil
        self.applyMode = nil
        self.settingsSnapshotBefore = nil
        self.settingsSnapshotAfter = nil
    }

    mutating func markApplied(mode: LoopInsightsApplyMode, snapshotBefore: LoopInsightsTherapySnapshot?, snapshotAfter: LoopInsightsTherapySnapshot?) {
        self.status = mode == .autoApply ? .autoApplied : .applied
        self.resolvedAt = Date()
        self.applyMode = mode
        self.settingsSnapshotBefore = snapshotBefore
        self.settingsSnapshotAfter = snapshotAfter
    }

    mutating func markDismissed() {
        self.status = .dismissed
        self.resolvedAt = Date()
    }

    static func == (lhs: LoopInsightsSuggestionRecord, rhs: LoopInsightsSuggestionRecord) -> Bool {
        return lhs.id == rhs.id
    }
}
