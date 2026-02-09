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

    enum AnalysisType: String, Codable {
        case image
        case dictation
    }
}
