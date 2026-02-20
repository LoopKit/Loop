//
//  LoopInsights_MealInsightsViewModel.swift
//  Loop
//
//  LoopInsights — Extracted ViewModel for Meal Insights view.
//  Manages meal data loading, debrief generation, and pre-meal advice state.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Combine
import LoopKit
import HealthKit

@MainActor
final class LoopInsights_MealInsightsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var mealEvents: [LoopInsightsMealEvent] = []
    @Published var foodPatterns: [LoopInsightsFoodResponsePattern] = []
    @Published var isLoading = true

    // Pre-Meal Advice tab
    @Published var selectedPattern: LoopInsightsFoodResponsePattern?
    @Published var aiAdvice: String?
    @Published var isLoadingAdvice = false

    // Debrief state per meal
    @Published var expandedDebriefID: String?
    @Published var debriefResults: [String: LoopInsights_MealDebrief] = [:]
    @Published var debriefLoadingIDs: Set<String> = []
    @Published var debriefErrors: [String: String] = [:]

    // MARK: - Dependencies

    let coordinator: LoopInsights_Coordinator

    init(coordinator: LoopInsights_Coordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Data Loading

    func loadMealData() async {
        let period = LoopInsights_FeatureFlags.analysisPeriod
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-period.timeInterval)

        do {
            let carbEntries = try await coordinator.fetchCarbEntries(start: startDate, end: endDate)
            let glucoseSamples = try await coordinator.fetchGlucoseSamples(start: startDate, end: endDate)

            let rawGlucoseEvents = LoopInsights_FoodResponseAnalyzer.buildRecentMealEvents(
                carbEntries: carbEntries,
                glucoseSamples: glucoseSamples
            )
            let patterns = LoopInsights_FoodResponseAnalyzer.analyzeFoodResponses(
                carbEntries: carbEntries,
                glucoseSamples: glucoseSamples
            )

            // Load FoodFinder MealArchive to get thumbnails + meals without glucose data
            let archiveMeals = MealArchive.meals(from: startDate, to: endDate)

            // Enrich glucose-matched events with thumbnail + nutrition from MealArchive
            let glucoseMatchedEvents = rawGlucoseEvents.map { event -> LoopInsightsMealEvent in
                let matchingRecord = archiveMeals.first { record in
                    abs(record.date.timeIntervalSince(event.date)) < 300 &&
                    record.foodType == event.foodType
                }
                guard let record = matchingRecord else { return event }
                let result = record.analysisResult
                return LoopInsightsMealEvent(
                    date: event.date,
                    foodType: event.foodType,
                    carbs: event.carbs,
                    preMealGlucose: event.preMealGlucose,
                    peakGlucose: event.peakGlucose,
                    twoHourGlucose: event.twoHourGlucose,
                    glucoseTimeline: event.glucoseTimeline,
                    archiveRecordID: record.id,
                    thumbnailID: record.thumbnailID,
                    totalProtein: result?.totalProtein,
                    totalFat: result?.totalFat,
                    totalFiber: result?.totalFiber,
                    totalCalories: result?.totalCalories
                )
            }

            // Archive-only meals (no glucose match yet)
            let archiveEvents = archiveMeals.compactMap { record -> LoopInsightsMealEvent? in
                let isDuplicate = glucoseMatchedEvents.contains { event in
                    abs(event.date.timeIntervalSince(record.date)) < 300 &&
                    event.foodType == record.foodType
                }
                guard !isDuplicate else { return nil }

                let result = record.analysisResult
                return LoopInsightsMealEvent(
                    date: record.date,
                    foodType: record.foodType,
                    carbs: record.carbsGrams,
                    archiveRecordID: record.id,
                    thumbnailID: record.thumbnailID,
                    totalProtein: result?.totalProtein,
                    totalFat: result?.totalFat,
                    totalFiber: result?.totalFiber,
                    totalCalories: result?.totalCalories
                )
            }

            // Merge, deduplicate, and sort by date (most recent first).
            // Dedup by date proximity (5 min) + foodType — keeps the version with more data.
            let merged = (glucoseMatchedEvents + archiveEvents).sorted { $0.date > $1.date }
            var seen: [(date: Date, foodType: String)] = []
            let deduplicated = merged.filter { event in
                let isDup = seen.contains { existing in
                    abs(existing.date.timeIntervalSince(event.date)) < 300 &&
                    existing.foodType == event.foodType
                }
                guard !isDup else { return false }
                seen.append((event.date, event.foodType))
                return true
            }
            self.mealEvents = deduplicated
            self.foodPatterns = patterns
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }

    // MARK: - Debrief

    /// Check debrief readiness for a meal event. Looks up the MealArchive record by date + foodType.
    func debriefReadiness(for event: LoopInsightsMealEvent) -> LoopInsights_DebriefReadiness {
        guard LoopInsights_FeatureFlags.mealDebriefEnabled else { return .featureDisabled }

        // Already loaded in this session?
        if debriefResults[event.id.uuidString] != nil { return .ready }

        // Find matching MealArchive record
        guard let record = findArchiveRecord(for: event) else { return .noSnapshot }

        return coordinator.mealDebriefService.isDebriefReady(for: record)
    }

    /// Toggle debrief expansion for a meal event. Generates on first expand if needed.
    func toggleDebrief(for event: LoopInsightsMealEvent) {
        let eventID = event.id.uuidString

        if expandedDebriefID == eventID {
            expandedDebriefID = nil
            return
        }

        expandedDebriefID = eventID

        // Already loaded or loading?
        if debriefResults[eventID] != nil || debriefLoadingIDs.contains(eventID) { return }

        guard let record = findArchiveRecord(for: event) else { return }

        let readiness = coordinator.mealDebriefService.isDebriefReady(for: record)
        guard readiness == .readyToGenerate || readiness == .ready else { return }

        // Find food pattern for this type
        let pattern = foodPatterns.first { $0.foodType == event.foodType }

        debriefLoadingIDs.insert(eventID)
        debriefErrors.removeValue(forKey: eventID)

        Task {
            do {
                let debrief = try await coordinator.mealDebriefService.generateDebrief(
                    for: record,
                    actualTimeline: event.glucoseTimeline,
                    foodPattern: pattern
                )
                self.debriefResults[eventID] = debrief
                self.debriefLoadingIDs.remove(eventID)
            } catch {
                self.debriefErrors[eventID] = error.localizedDescription
                self.debriefLoadingIDs.remove(eventID)
            }
        }
    }

    // MARK: - Pre-Meal Advice

    func requestAdvice(for pattern: LoopInsightsFoodResponsePattern) {
        selectedPattern = pattern
        isLoadingAdvice = true
        aiAdvice = nil

        let prompt = """
        Based on my glucose response pattern for \(pattern.foodType):
        - Average carbs: \(String(format: "%.0f", pattern.averageCarbsPerMeal))g per meal
        - Peak glucose rise: \(String(format: "%.0f", pattern.peakGlucoseRise)) mg/dL
        - Time to peak: \(String(format: "%.0f", pattern.timeToPeakMinutes)) minutes
        - 2h post-meal average: \(String(format: "%.0f", pattern.twoHourPostMealAvg)) mg/dL
        - 4h post-meal average: \(String(format: "%.0f", pattern.fourHourPostMealAvg)) mg/dL

        Give me brief, practical advice for managing this food. Include: timing of pre-bolus, \
        any carb ratio considerations, and alternative strategies. Keep it under 4 sentences.
        """

        Task {
            do {
                let response = try await LoopInsights_AIServiceAdapter.shared.sendPrompt(
                    "You are a diabetes meal advisor. Be concise and practical.",
                    userPrompt: prompt
                )
                self.aiAdvice = response
                self.isLoadingAdvice = false
            } catch {
                self.aiAdvice = "Unable to get advice: \(error.localizedDescription)"
                self.isLoadingAdvice = false
            }
        }
    }

    // MARK: - Helpers

    /// Find the MealArchive record that matches this meal event.
    /// Uses archiveRecordID if available, otherwise falls back to date proximity + foodType.
    private func findArchiveRecord(for event: LoopInsightsMealEvent) -> FoodFinder_AnalysisRecord? {
        if let recordID = event.archiveRecordID {
            return MealArchive.loadAll().first { $0.id == recordID }
        }
        let windowStart = event.date.addingTimeInterval(-300) // 5 min tolerance
        let windowEnd = event.date.addingTimeInterval(300)
        let candidates = MealArchive.meals(from: windowStart, to: windowEnd)
        return candidates.first { $0.foodType == event.foodType }
            ?? candidates.first // Fall back to closest match
    }
}
