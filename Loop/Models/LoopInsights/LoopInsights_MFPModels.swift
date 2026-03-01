//
//  LoopInsights_MFPModels.swift
//  Loop
//
//  LoopInsights — Data models for MyFitnessPal diary import.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - MFP Authentication Data

/// Bearer token and user ID returned by MFP's auth_token endpoint.
struct LoopInsights_MFPAuthData: Codable {
    let userId: String
    let accessToken: String
}

// MARK: - MFP Configuration

struct LoopInsights_MFPConfig: Codable {
    var isEnabled: Bool
    var lastSyncDate: Date?
    var defaultMealTimes: [String: Int]

    static let defaultMealTimes: [String: Int] = [
        "Breakfast": 8,
        "Lunch": 12,
        "Dinner": 18,
        "Snacks": 15
    ]

    init(isEnabled: Bool = false, lastSyncDate: Date? = nil) {
        self.isEnabled = isEnabled
        self.lastSyncDate = lastSyncDate
        self.defaultMealTimes = Self.defaultMealTimes
    }
}

// MARK: - MFP Diary Entry (Meals)

struct LoopInsights_MFPDiaryEntry: Codable, Equatable {
    let name: String
    let calories: Double
    let carbs: Double
    let fat: Double
    let protein: Double
    let mealType: String
    let date: Date

    /// Estimated timestamp combining the diary date with the default hour for this meal type.
    func estimatedTimestamp(mealTimes: [String: Int] = LoopInsights_MFPConfig.defaultMealTimes) -> Date {
        let hour = mealTimes[mealType] ?? 12
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        return calendar.date(from: components) ?? date
    }
}

// MARK: - MFP Exercise Entry

struct LoopInsights_MFPExerciseEntry: Codable, Equatable {
    let name: String
    let caloriesBurned: Double
    let durationMinutes: Double
    let date: Date
}

// MARK: - MFP Sync Summary

/// Results from a full MFP diary sync — includes counts for all imported data types.
struct LoopInsights_MFPSyncSummary {
    let mealsImported: Int
    let exercisesImported: Int

    var totalImported: Int { mealsImported + exercisesImported }

    var displayString: String {
        var parts: [String] = []
        if mealsImported > 0 {
            parts.append("\(mealsImported) meal\(mealsImported == 1 ? "" : "s")")
        }
        if exercisesImported > 0 {
            parts.append("\(exercisesImported) exercise\(exercisesImported == 1 ? "" : "s")")
        }
        if parts.isEmpty { return "No new data" }
        return "Imported \(parts.joined(separator: ", "))"
    }
}

// MARK: - MFP v2 API Response

/// Maps to the MyFitnessPal v2 diary API JSON response.
/// Endpoint: GET api.myfitnesspal.com/v2/diary?entry_date=YYYY-MM-DD&types=diary_meal,exercise&fields[]=nutritional_contents&fields[]=exercise&fields[]=energy
struct LoopInsights_MFPDiaryResponse: Decodable {
    let items: [MFPDiaryItem]

    struct MFPDiaryItem: Decodable {
        let type: String?
        let date: String?
        let diary_meal: String?
        let nutritional_contents: NutritionContents?
        let exercise: ExerciseData?

        struct NutritionContents: Decodable {
            let carbohydrates: Double?
            let fat: Double?
            let protein: Double?
            let fiber: Double?
            let sugar: Double?
            let energy: EnergyValue?
        }

        struct ExerciseData: Decodable {
            let description: String?
            let duration: Double?
            let energy: EnergyValue?
        }

        struct EnergyValue: Decodable {
            let value: Double?
            let unit: String?
        }
    }
}
