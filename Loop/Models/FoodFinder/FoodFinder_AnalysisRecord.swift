//
//  FoodFinder_AnalysisRecord.swift
//  Loop
//
//  FoodFinder — Codable record for a single AI food analysis,
//  used by the Analysis History feature for quick re-entry.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

struct FoodFinder_AnalysisRecord: Codable, Identifiable, Equatable {
    static func == (lhs: FoodFinder_AnalysisRecord, rhs: FoodFinder_AnalysisRecord) -> Bool {
        lhs.id == rhs.id
    }

    let id: String
    let name: String
    let carbsGrams: Double
    let foodType: String
    let absorptionTime: TimeInterval
    let analysisType: AnalysisType
    let date: Date
    let thumbnailID: String?
    let analysisResult: AIFoodAnalysisResult?

    // MARK: - LoopInsights Preparation
    //
    // These fields capture what the AI originally suggested vs what the user
    // actually entered. The delta between them is the single most valuable
    // signal for LoopInsights: it reveals systematic over/under-estimation
    // by food type, time of day, or confidence level — which directly informs
    // Carb Ratio and ISF tuning recommendations.

    /// The AI's original carb estimate before any user edits (nil for legacy records).
    let originalAICarbs: Double?

    /// The confidence percentage the AI reported (nil for legacy records).
    let aiConfidencePercent: Int?

    enum AnalysisType: String, Codable {
        case image
        case dictation
    }
}
