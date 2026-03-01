//
//  LoopInsights_MFPImporter.swift
//  Loop
//
//  LoopInsights — MyFitnessPal authenticated diary importer service.
//  Uses WKWebView login + v2 API with bearer token authentication.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - MFP Importer

enum LoopInsights_MFPImporter {

    enum MFPError: LocalizedError {
        case notConnected
        case sessionExpired
        case networkError(String)
        case parseError
        case noEntries

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Not connected to MyFitnessPal. Tap \"Connect\" to sign in."
            case .sessionExpired:
                return "Your MyFitnessPal session has expired. Please reconnect."
            case .networkError(let detail):
                return "Network error: \(detail)"
            case .parseError:
                return "Could not parse the diary response. The MFP format may have changed."
            case .noEntries:
                return "No entries found for this date."
            }
        }
    }

    // MARK: - Constants

    private static let mfpAPIBaseURL = "https://api.myfitnesspal.com"
    private static let diaryPath = "/v2/diary"
    private static let clientID = "mfp-main-js"

    // MARK: - Token Exchange

    /// Parses the JSON response from MFP's /user/auth_token endpoint.
    /// Called after WKWebView login with the auth_token JSON fetched via JavaScript.
    static func parseAuthResponse(_ json: String) -> LoopInsights_MFPAuthData? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = dict["access_token"] as? String else {
            return nil
        }

        // user_id may be a string or number
        let userId: String
        if let strId = dict["user_id"] as? String {
            userId = strId
        } else if let numId = dict["user_id"] as? Int {
            userId = String(numId)
        } else if let numId = dict["user_id"] as? Int64 {
            userId = String(numId)
        } else {
            return nil
        }

        return LoopInsights_MFPAuthData(userId: userId, accessToken: accessToken)
    }

    // MARK: - Test Connection

    /// Verifies the stored bearer token is valid by fetching today's diary.
    /// Returns the number of items found.
    static func testConnection() async throws -> Int {
        let (meals, exercises) = try await fetchDiary(date: Date())
        return meals.count + exercises.count
    }

    // MARK: - Fetch Diary

    /// Fetches all meal and exercise entries from the authenticated user's diary for a given date.
    /// Uses the MFP v2 API with bearer token authentication.
    static func fetchDiary(date: Date) async throws -> (meals: [LoopInsights_MFPDiaryEntry], exercises: [LoopInsights_MFPExerciseEntry]) {
        guard let auth = LoopInsights_SecureStorage.loadMFPAuth() else {
            throw MFPError.notConnected
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        var components = URLComponents(string: "\(mfpAPIBaseURL)\(diaryPath)")!
        components.queryItems = [
            URLQueryItem(name: "entry_date", value: dateString),
            URLQueryItem(name: "types", value: "diary_meal,exercise"),
            URLQueryItem(name: "fields[]", value: "nutritional_contents"),
            URLQueryItem(name: "fields[]", value: "exercise"),
            URLQueryItem(name: "fields[]", value: "energy")
        ]

        guard let url = components.url else {
            throw MFPError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "mfp-client-id")
        request.setValue(auth.userId, forHTTPHeaderField: "mfp-user-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MFPError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            LoopInsights_SecureStorage.deleteMFPAuth()
            throw MFPError.sessionExpired
        default:
            throw MFPError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let diaryResponse: LoopInsights_MFPDiaryResponse
        do {
            diaryResponse = try JSONDecoder().decode(LoopInsights_MFPDiaryResponse.self, from: data)
        } catch {
            throw MFPError.parseError
        }

        // Parse meal entries
        let meals = diaryResponse.items.compactMap { item -> LoopInsights_MFPDiaryEntry? in
            guard item.type == "diary_meal",
                  let mealType = item.diary_meal,
                  let nutrition = item.nutritional_contents else { return nil }

            let calories = nutrition.energy?.value ?? 0
            let carbs = nutrition.carbohydrates ?? 0
            let fat = nutrition.fat ?? 0
            let protein = nutrition.protein ?? 0

            guard calories > 0 || carbs > 0 else { return nil }

            return LoopInsights_MFPDiaryEntry(
                name: mealType,
                calories: calories,
                carbs: carbs,
                fat: fat,
                protein: protein,
                mealType: mealType,
                date: date
            )
        }

        // Parse exercise entries
        let exercises = diaryResponse.items.compactMap { item -> LoopInsights_MFPExerciseEntry? in
            guard item.type == "exercise",
                  let exerciseData = item.exercise else { return nil }

            let name = exerciseData.description ?? "Exercise"
            let calories = exerciseData.energy?.value ?? 0
            let duration = exerciseData.duration ?? 0

            guard calories > 0 || duration > 0 else { return nil }

            return LoopInsights_MFPExerciseEntry(
                name: name,
                caloriesBurned: calories,
                durationMinutes: duration,
                date: date
            )
        }

        return (meals, exercises)
    }

    // MARK: - Sync All Data

    /// Fetches all diary data since the last sync date — meals and exercise.
    /// Meals are archived in MealArchive; exercise is archived in MFPExerciseArchive.
    /// Returns a summary of what was imported.
    @discardableResult
    static func syncDiary(since lastSync: Date?) async throws -> LoopInsights_MFPSyncSummary {
        guard LoopInsights_SecureStorage.hasMFPAuth else {
            throw MFPError.notConnected
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = lastSync.map { calendar.startOfDay(for: $0) } ?? today

        var allMeals: [LoopInsights_MFPDiaryEntry] = []
        var allExercises: [LoopInsights_MFPExerciseEntry] = []

        // Fetch each day from startDate to today
        var currentDate = startDate
        while currentDate <= today {
            do {
                let (meals, exercises) = try await fetchDiary(date: currentDate)
                allMeals.append(contentsOf: meals)
                allExercises.append(contentsOf: exercises)
            } catch MFPError.noEntries {
                // No entries for this day is fine
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? today.addingTimeInterval(86400)
        }

        // Import meals
        let mealsImported = importMeals(allMeals)

        // Import exercise
        let exercisesImported = importExercises(allExercises)

        // Update last sync date
        LoopInsights_FeatureFlags.mfpLastSyncDate = Date()

        #if DEBUG
        print("LoopInsights MFP: Imported \(mealsImported) meals, \(exercisesImported) exercises")
        #endif

        return LoopInsights_MFPSyncSummary(
            mealsImported: mealsImported,
            exercisesImported: exercisesImported
        )
    }

    // MARK: - Disconnect

    /// Clears stored MFP credentials and resets connection state.
    static func disconnect() {
        LoopInsights_SecureStorage.deleteMFPAuth()
        LoopInsights_FeatureFlags.mfpLastSyncDate = nil
    }

    // MARK: - Exercise Archive

    private static var exerciseArchiveURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LoopInsights", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MFPExercise.json")
    }

    /// Loads all stored MFP exercise entries.
    static func loadExercises() -> [LoopInsights_MFPExerciseEntry] {
        guard let data = try? Data(contentsOf: exerciseArchiveURL),
              let entries = try? JSONDecoder().decode([LoopInsights_MFPExerciseEntry].self, from: data) else {
            return []
        }
        return entries
    }

    /// Loads MFP exercise entries within the specified lookback period.
    static func loadExercises(since date: Date) -> [LoopInsights_MFPExerciseEntry] {
        return loadExercises().filter { $0.date >= date }
    }

    private static func saveExercises(_ entries: [LoopInsights_MFPExerciseEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: exerciseArchiveURL)
        }
    }

    // MARK: - Private Import Helpers

    private static func importMeals(_ entries: [LoopInsights_MFPDiaryEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }

        let existingMeals = MealArchive.loadAll()
        var importCount = 0

        for entry in entries {
            let timestamp = entry.estimatedTimestamp()

            // Cross-source dedup: match on carbs (±5g) + time (±2h), ignoring name.
            // MFP uses meal-type names ("Lunch") while FoodFinder uses food names ("Pizza"),
            // so name matching would miss duplicates across sources.
            let isDuplicate = existingMeals.contains { existing in
                abs(existing.date.timeIntervalSince(timestamp)) < 7200 &&
                abs(existing.carbsGrams - entry.carbs) < 5
            }
            guard !isDuplicate else { continue }

            let record = FoodFinder_AnalysisRecord(
                id: UUID().uuidString,
                name: entry.name,
                carbsGrams: entry.carbs,
                foodType: mfpFoodType(for: entry),
                absorptionTime: mfpAbsorptionTime(for: entry),
                analysisType: .mfpImport,
                date: timestamp,
                thumbnailID: nil,
                analysisResult: mfpAnalysisResult(for: entry),
                originalAICarbs: nil,
                aiConfidencePercent: nil,
                latitude: nil,
                longitude: nil,
                locationName: nil
            )

            MealArchive.archive(record)
            NotificationCenter.default.post(
                name: .foodFinderMealLogged,
                object: nil,
                userInfo: ["recordID": record.id]
            )
            importCount += 1
        }

        return importCount
    }

    private static func importExercises(_ entries: [LoopInsights_MFPExerciseEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }

        var existing = loadExercises()
        var importCount = 0

        for entry in entries {
            // Deduplicate: same name + date within 1 hour + same calories
            let isDuplicate = existing.contains { ex in
                abs(ex.date.timeIntervalSince(entry.date)) < 3600 &&
                ex.name.lowercased() == entry.name.lowercased() &&
                abs(ex.caloriesBurned - entry.caloriesBurned) < 1
            }
            guard !isDuplicate else { continue }

            existing.append(entry)
            importCount += 1
        }

        if importCount > 0 {
            // Prune entries older than 90 days
            let cutoff = Date().addingTimeInterval(-90 * 86400)
            existing = existing.filter { $0.date >= cutoff }
            saveExercises(existing)
        }

        return importCount
    }

    // MARK: - Private Meal Helpers

    private static func mfpFoodType(for entry: LoopInsights_MFPDiaryEntry) -> String {
        let totalMacros = entry.carbs + entry.fat + entry.protein
        guard totalMacros > 0 else { return "Mixed" }
        let carbRatio = entry.carbs / totalMacros
        if carbRatio > 0.7 { return "High Carb" }
        if entry.fat / totalMacros > 0.5 { return "High Fat" }
        return "Mixed"
    }

    private static func mfpAbsorptionTime(for entry: LoopInsights_MFPDiaryEntry) -> TimeInterval {
        let totalMacros = entry.carbs + entry.fat + entry.protein
        guard totalMacros > 0 else { return 10800 }
        let fatRatio = entry.fat / totalMacros
        if fatRatio > 0.4 { return 18000 }
        if fatRatio > 0.2 { return 14400 }
        return 10800
    }

    private static func mfpAnalysisResult(for entry: LoopInsights_MFPDiaryEntry) -> AIFoodAnalysisResult {
        let item = FoodItemAnalysis(
            name: entry.name,
            portionEstimate: "1 serving",
            usdaServingSize: nil,
            servingMultiplier: 1.0,
            preparationMethod: nil,
            visualCues: nil,
            carbohydrates: entry.carbs,
            calories: entry.calories,
            fat: entry.fat,
            fiber: nil,
            protein: entry.protein,
            assessmentNotes: "Imported from MyFitnessPal (\(entry.mealType))",
            absorptionTimeHours: nil
        )
        return AIFoodAnalysisResult(
            imageType: nil,
            foodItemsDetailed: [item],
            overallDescription: "MyFitnessPal import — \(entry.mealType)",
            confidence: .high,
            numericConfidence: nil,
            totalFoodPortions: 1,
            totalUsdaServings: nil,
            totalCarbohydrates: entry.carbs,
            totalProtein: entry.protein,
            totalFat: entry.fat,
            totalFiber: nil,
            totalCalories: entry.calories,
            portionAssessmentMethod: "MyFitnessPal diary",
            diabetesConsiderations: nil,
            visualAssessmentDetails: nil,
            notes: nil,
            originalServings: 1.0,
            fatProteinUnits: nil,
            netCarbsAdjustment: nil,
            insulinTimingRecommendations: nil,
            fpuDosingGuidance: nil,
            exerciseConsiderations: nil,
            absorptionTimeHours: nil,
            absorptionTimeReasoning: nil,
            mealSizeImpact: nil,
            individualizationFactors: nil,
            safetyAlerts: nil
        )
    }
}
