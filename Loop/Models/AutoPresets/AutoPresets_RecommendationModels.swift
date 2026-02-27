//
//  AutoPresets_RecommendationModels.swift
//  Loop
//
//  AutoPresets — Data models for AI-generated preset recommendations.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

// MARK: - Recommendation

/// An AI-generated recommendation for a new override preset
struct AutoPresetsRecommendation: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let reasoning: String
    let confidence: AutoPresetsRecommendationConfidence
    let insulinNeedsScale: Double?
    let targetRangeLowMgdl: Double?
    let targetRangeHighMgdl: Double?
    let durationMinutes: Int
    let triggerContext: AutoPresetsTriggerContext
    let patternDescription: String
}

// MARK: - Confidence Level

enum AutoPresetsRecommendationConfidence: String, Codable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

// MARK: - Trigger Context

enum AutoPresetsTriggerContext: String, Codable {
    case meal
    case exercise
    case timeOfDay
    case dayOfWeek

    var displayName: String {
        switch self {
        case .meal: return "Meal"
        case .exercise: return "Exercise"
        case .timeOfDay: return "Time of Day"
        case .dayOfWeek: return "Day of Week"
        }
    }

    var iconName: String {
        switch self {
        case .meal: return "fork.knife"
        case .exercise: return "figure.run"
        case .timeOfDay: return "clock"
        case .dayOfWeek: return "calendar"
        }
    }
}

// MARK: - Safety Guardrails

enum AutoPresetsAdvisorGuardrails {
    static let minInsulinScale: Double = 0.5
    static let maxInsulinScale: Double = 2.0
    static let minTargetLow: Double = 67     // mg/dL
    static let maxTargetLow: Double = 160    // mg/dL
    static let minTargetHigh: Double = 90    // mg/dL
    static let maxTargetHigh: Double = 180   // mg/dL
    static let minDurationMinutes: Int = 30
    static let maxDurationMinutes: Int = 720 // 12 hours
}

// MARK: - AI Response

/// Parsed AI response containing recommendations and overall assessment
struct AutoPresetsAIResponse {
    let recommendations: [AutoPresetsRecommendation]
    let overallAssessment: String
}
