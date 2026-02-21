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

            // Glucose events from carb entries (used for glucose timeline matching only)
            let glucoseEvents = LoopInsights_FoodResponseAnalyzer.buildRecentMealEvents(
                carbEntries: carbEntries,
                glucoseSamples: glucoseSamples
            )
            let patterns = LoopInsights_FoodResponseAnalyzer.analyzeFoodResponses(
                carbEntries: carbEntries,
                glucoseSamples: glucoseSamples
            )

            // --- Archive-first approach ---
            // MealArchive is the single source of truth for FoodFinder meals.
            // It has the real food name, thumbnail, and nutritional data.
            // We attach glucose data to archive records by date+carbs matching,
            // then add carb-only entries (non-FoodFinder meals) separately.

            let archiveMeals = MealArchive.meals(from: startDate, to: endDate)
            var consumedGlucoseEventIndices = Set<Int>()
            var events: [LoopInsightsMealEvent] = []

            // 1. Build events from archive records, attaching glucose data when available
            for record in archiveMeals {
                let result = record.analysisResult

                // Find the glucose event that matches this archive record
                let matchIdx = glucoseEvents.indices.first { idx in
                    !consumedGlucoseEventIndices.contains(idx) &&
                    abs(glucoseEvents[idx].date.timeIntervalSince(record.date)) < 300 &&
                    abs(glucoseEvents[idx].carbs - record.carbsGrams) < 1
                }

                if let idx = matchIdx {
                    consumedGlucoseEventIndices.insert(idx)
                    let ge = glucoseEvents[idx]
                    events.append(LoopInsightsMealEvent(
                        date: ge.date,
                        foodType: record.foodType,
                        carbs: ge.carbs,
                        preMealGlucose: ge.preMealGlucose,
                        peakGlucose: ge.peakGlucose,
                        twoHourGlucose: ge.twoHourGlucose,
                        glucoseTimeline: ge.glucoseTimeline,
                        archiveRecordID: record.id,
                        thumbnailID: record.thumbnailID,
                        totalProtein: result?.totalProtein,
                        totalFat: result?.totalFat,
                        totalFiber: result?.totalFiber,
                        totalCalories: result?.totalCalories
                    ))
                } else {
                    // No glucose match yet — show archive record without glucose data
                    events.append(LoopInsightsMealEvent(
                        date: record.date,
                        foodType: record.foodType,
                        carbs: record.carbsGrams,
                        archiveRecordID: record.id,
                        thumbnailID: record.thumbnailID,
                        totalProtein: result?.totalProtein,
                        totalFat: result?.totalFat,
                        totalFiber: result?.totalFiber,
                        totalCalories: result?.totalCalories
                    ))
                }
            }

            // 2. Add remaining glucose events that didn't match any archive record
            //    (these are manual carb entries without FoodFinder)
            for (idx, ge) in glucoseEvents.enumerated() where !consumedGlucoseEventIndices.contains(idx) {
                events.append(ge)
            }

            // 3. Add remaining CarbStore entries not yet represented.
            //    Catches manual carb entries that lacked sufficient glucose data
            //    for buildRecentMealEvents() but should still appear in the meal list.
            for entry in carbEntries {
                let entryDate = entry.startDate
                let entryCarbs = entry.quantity.doubleValue(for: .gram())
                guard entryCarbs > 0 else { continue }

                let alreadyRepresented = events.contains { event in
                    abs(event.date.timeIntervalSince(entryDate)) < 300 &&
                    abs(event.carbs - entryCarbs) < 1
                }
                guard !alreadyRepresented else { continue }

                events.append(LoopInsightsMealEvent(
                    date: entryDate,
                    foodType: entry.foodType ?? "Unknown",
                    carbs: entryCarbs
                ))
            }

            self.mealEvents = events.sorted { $0.date > $1.date }
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
    /// Uses archiveRecordID if available, otherwise falls back to date + carb proximity.
    private func findArchiveRecord(for event: LoopInsightsMealEvent) -> FoodFinder_AnalysisRecord? {
        if let recordID = event.archiveRecordID {
            return MealArchive.loadAll().first { $0.id == recordID }
        }
        let windowStart = event.date.addingTimeInterval(-300) // 5 min tolerance
        let windowEnd = event.date.addingTimeInterval(300)
        let candidates = MealArchive.meals(from: windowStart, to: windowEnd)
        return candidates.first { abs($0.carbsGrams - event.carbs) < 1 }
            ?? candidates.first // Fall back to closest match
    }
}
