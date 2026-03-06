//
//  LoopInsights_SuggestionRecord.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

// MARK: - Outcome Evaluation

/// The AI's evaluation of whether a previously applied suggestion achieved its success criteria
struct LoopInsightsOutcomeEvaluation: Codable, Equatable {
    let evaluatedAt: Date
    let criteriaMetCount: Int
    let criteriaTotalCount: Int
    let verdict: Verdict
    let reasoning: String

    enum Verdict: String, Codable, Equatable {
        case success
        case partial
        case noImprovement
        case worsened
        case insufficientData

        var displayName: String {
            switch self {
            case .success:
                return NSLocalizedString("Success", comment: "LoopInsights outcome: change worked")
            case .partial:
                return NSLocalizedString("Partial", comment: "LoopInsights outcome: some improvement")
            case .noImprovement:
                return NSLocalizedString("No Improvement", comment: "LoopInsights outcome: no change")
            case .worsened:
                return NSLocalizedString("Worsened", comment: "LoopInsights outcome: got worse")
            case .insufficientData:
                return NSLocalizedString("Too Early", comment: "LoopInsights outcome: not enough data yet")
            }
        }

        var systemImage: String {
            switch self {
            case .success: return "checkmark.seal.fill"
            case .partial: return "checkmark.circle"
            case .noImprovement: return "minus.circle"
            case .worsened: return "exclamationmark.triangle.fill"
            case .insufficientData: return "clock.badge.questionmark"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .partial: return .blue
            case .noImprovement: return .orange
            case .worsened: return .red
            case .insufficientData: return .gray
            }
        }
    }
}

// MARK: - Suggestion Status

/// The lifecycle status of a suggestion
enum LoopInsightsSuggestionStatus: String, Codable {
    case pending = "pending"
    case applied = "applied"
    case dismissed = "dismissed"
    case autoApplied = "auto_applied"
    case reverted = "reverted"

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
        case .reverted:
            return NSLocalizedString("Reverted", comment: "LoopInsights suggestion status: changes reverted")
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .applied: return "checkmark.circle.fill"
        case .dismissed: return "xmark.circle"
        case .autoApplied: return "bolt.circle.fill"
        case .reverted: return "arrow.uturn.backward.circle.fill"
        }
    }

    var isResolved: Bool {
        switch self {
        case .pending: return false
        case .applied, .dismissed, .autoApplied, .reverted: return true
        }
    }

    var isRevertable: Bool {
        switch self {
        case .applied, .autoApplied: return true
        case .pending, .dismissed, .reverted: return false
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
    var outcomeEvaluation: LoopInsightsOutcomeEvaluation?

    init(suggestion: LoopInsightsSuggestion) {
        self.id = UUID()
        self.suggestion = suggestion
        self.status = .pending
        self.createdAt = Date()
        self.resolvedAt = nil
        self.applyMode = nil
        self.settingsSnapshotBefore = nil
        self.settingsSnapshotAfter = nil
        self.outcomeEvaluation = nil
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

    mutating func markReverted() {
        self.status = .reverted
        self.resolvedAt = Date()
    }

    static func == (lhs: LoopInsightsSuggestionRecord, rhs: LoopInsightsSuggestionRecord) -> Bool {
        return lhs.id == rhs.id
    }
}
