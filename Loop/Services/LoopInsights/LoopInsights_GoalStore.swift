//
//  LoopInsights_GoalStore.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Goal Type

/// Types of clinical goals users can track
enum LoopInsightsGoalType: String, Codable, CaseIterable, Identifiable {
    case tirTarget = "tir_target"
    case a1cTarget = "a1c_target"
    case hypoReduction = "hypo_reduction"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tirTarget:
            return NSLocalizedString("Time in Range", comment: "LoopInsights goal type: TIR target")
        case .a1cTarget:
            return NSLocalizedString("A1C Estimate", comment: "LoopInsights goal type: A1C target")
        case .hypoReduction:
            return NSLocalizedString("Below Range", comment: "LoopInsights goal type: hypo reduction")
        case .custom:
            return NSLocalizedString("Custom Goal", comment: "LoopInsights goal type: custom")
        }
    }

    var icon: String {
        switch self {
        case .tirTarget: return "target"
        case .a1cTarget: return "chart.line.downtrend.xyaxis"
        case .hypoReduction: return "arrow.down.circle"
        case .custom: return "star"
        }
    }

    var unit: String {
        switch self {
        case .tirTarget: return "%"
        case .a1cTarget: return "%"
        case .hypoReduction: return "%"
        case .custom: return ""
        }
    }

    /// Default target value for each goal type
    var defaultTarget: Double {
        switch self {
        case .tirTarget: return 80
        case .a1cTarget: return 6.5
        case .hypoReduction: return 2
        case .custom: return 0
        }
    }

    /// Whether lower is better (e.g., A1C, below-range %)
    var lowerIsBetter: Bool {
        switch self {
        case .tirTarget: return false
        case .a1cTarget: return true
        case .hypoReduction: return true
        case .custom: return false
        }
    }
}

// MARK: - Goal Model

/// A user-set clinical goal with progress tracking
struct LoopInsightsGoal: Codable, Identifiable {
    let id: UUID
    let type: LoopInsightsGoalType
    var targetValue: Double
    var currentValue: Double
    var customLabel: String?
    let createdAt: Date
    var achieved: Bool

    init(type: LoopInsightsGoalType, targetValue: Double, currentValue: Double = 0, customLabel: String? = nil) {
        self.id = UUID()
        self.type = type
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.customLabel = customLabel
        self.createdAt = Date()
        self.achieved = false
    }

    /// Display label (uses customLabel for custom goals, otherwise type displayName)
    var displayLabel: String {
        if type == .custom, let label = customLabel, !label.isEmpty {
            return label
        }
        return type.displayName
    }

    /// Progress from 0.0 to 1.0
    var progress: Double {
        guard targetValue != 0 else { return 0 }
        if type.lowerIsBetter {
            // For lower-is-better goals: progress increases as current drops toward/below target
            guard currentValue > 0 else { return 1.0 }
            // If current is at or below target, we're done
            if currentValue <= targetValue { return 1.0 }
            // Use a reasonable "starting" value to measure progress from
            let startValue = max(targetValue * 3, currentValue)
            let range = startValue - targetValue
            guard range > 0 else { return 1.0 }
            return min(1.0, max(0, (startValue - currentValue) / range))
        } else {
            return min(1.0, max(0, currentValue / targetValue))
        }
    }
}

// MARK: - Mood Tag

/// Mood tag for reflections
enum LoopInsightsMoodTag: String, Codable, CaseIterable, Identifiable {
    case great
    case good
    case okay
    case tough

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .great: return NSLocalizedString("Great", comment: "LoopInsights mood: great")
        case .good: return NSLocalizedString("Good", comment: "LoopInsights mood: good")
        case .okay: return NSLocalizedString("Okay", comment: "LoopInsights mood: okay")
        case .tough: return NSLocalizedString("Tough", comment: "LoopInsights mood: tough")
        }
    }

    var emoji: String {
        switch self {
        case .great: return "😊"
        case .good: return "🙂"
        case .okay: return "😐"
        case .tough: return "😓"
        }
    }

    var color: String {
        switch self {
        case .great: return "green"
        case .good: return "blue"
        case .okay: return "orange"
        case .tough: return "red"
        }
    }
}

// MARK: - Reflection Model

/// A timestamped journal entry with mood tag
struct LoopInsightsReflection: Codable, Identifiable {
    let id: UUID
    let text: String
    let mood: LoopInsightsMoodTag
    let timestamp: Date

    init(text: String, mood: LoopInsightsMoodTag) {
        self.id = UUID()
        self.text = text
        self.mood = mood
        self.timestamp = Date()
    }
}

// MARK: - Cached Pattern Model

/// An AI-discovered pattern cached per session
struct LoopInsightsCachedPattern: Codable, Identifiable {
    let id: UUID
    let type: String
    let description: String
    let severity: String
    let detectedAt: Date
    let expiresAt: Date

    init(type: String, description: String, severity: String, ttlMinutes: Int = 60) {
        self.id = UUID()
        self.type = type
        self.description = description
        self.severity = severity
        self.detectedAt = Date()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(ttlMinutes * 60))
    }

    var isExpired: Bool {
        return Date() > expiresAt
    }
}

// MARK: - Goal Store

/// Singleton store for LoopInsights goals, reflections, and cached patterns.
/// UserDefaults-backed JSON persistence.
final class LoopInsights_GoalStore: ObservableObject {

    static let shared = LoopInsights_GoalStore()

    private static let goalsKey = "LoopInsights_Goals"
    private static let reflectionsKey = "LoopInsights_Reflections"
    private static let patternsKey = "LoopInsights_CachedPatterns"

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published private(set) var goals: [LoopInsightsGoal] = []
    @Published private(set) var reflections: [LoopInsightsReflection] = []
    @Published private(set) var cachedPatterns: [LoopInsightsCachedPattern] = []

    private init() {
        loadGoals()
        loadReflections()
        loadPatterns()
    }

    // MARK: - Goals API

    /// Add a new goal
    @discardableResult
    func addGoal(type: LoopInsightsGoalType, targetValue: Double, customLabel: String? = nil) -> LoopInsightsGoal {
        let goal = LoopInsightsGoal(type: type, targetValue: targetValue, customLabel: customLabel)
        goals.append(goal)
        saveGoals()
        return goal
    }

    /// Update goal's current value and check achievement
    func updateGoal(id: UUID, currentValue: Double) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].currentValue = currentValue

        // Check if goal is achieved
        let goal = goals[index]
        if goal.type.lowerIsBetter {
            goals[index].achieved = currentValue <= goal.targetValue
        } else {
            goals[index].achieved = currentValue >= goal.targetValue
        }

        saveGoals()
    }

    /// Delete a goal
    func deleteGoal(id: UUID) {
        goals.removeAll { $0.id == id }
        saveGoals()
    }

    /// All goals sorted by creation date (newest first)
    var allGoals: [LoopInsightsGoal] {
        return goals.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Reflections API

    /// Add a new reflection
    @discardableResult
    func addReflection(text: String, mood: LoopInsightsMoodTag) -> LoopInsightsReflection {
        let reflection = LoopInsightsReflection(text: text, mood: mood)
        reflections.append(reflection)
        saveReflections()
        return reflection
    }

    /// Delete a reflection
    func deleteReflection(id: UUID) {
        reflections.removeAll { $0.id == id }
        saveReflections()
    }

    /// All reflections sorted by timestamp (newest first)
    var allReflections: [LoopInsightsReflection] {
        return reflections.sorted { $0.timestamp > $1.timestamp }
    }

    /// Most recent N reflections
    func recentReflections(limit: Int = 5) -> [LoopInsightsReflection] {
        return Array(allReflections.prefix(limit))
    }

    // MARK: - Pattern Cache API

    /// Cache AI-discovered patterns
    func cachePatterns(_ patterns: [LoopInsightsCachedPattern]) {
        cachedPatterns = patterns
        savePatterns()
    }

    /// Get non-expired cached patterns
    var validPatterns: [LoopInsightsCachedPattern] {
        return cachedPatterns.filter { !$0.isExpired }
    }

    /// Clear expired patterns
    func pruneExpiredPatterns() {
        let before = cachedPatterns.count
        cachedPatterns.removeAll { $0.isExpired }
        if cachedPatterns.count != before {
            savePatterns()
        }
    }

    // MARK: - Persistence

    private func loadGoals() {
        guard let data = defaults.data(forKey: Self.goalsKey) else {
            goals = []
            return
        }
        do {
            goals = try decoder.decode([LoopInsightsGoal].self, from: data)
        } catch {
            print("[LoopInsights] Failed to decode goals: \(error)")
            goals = []
        }
    }

    private func saveGoals() {
        do {
            let data = try encoder.encode(goals)
            defaults.set(data, forKey: Self.goalsKey)
        } catch {
            print("[LoopInsights] Failed to encode goals: \(error)")
        }
    }

    private func loadReflections() {
        guard let data = defaults.data(forKey: Self.reflectionsKey) else {
            reflections = []
            return
        }
        do {
            reflections = try decoder.decode([LoopInsightsReflection].self, from: data)
        } catch {
            print("[LoopInsights] Failed to decode reflections: \(error)")
            reflections = []
        }
    }

    private func saveReflections() {
        do {
            let data = try encoder.encode(reflections)
            defaults.set(data, forKey: Self.reflectionsKey)
        } catch {
            print("[LoopInsights] Failed to encode reflections: \(error)")
        }
    }

    private func loadPatterns() {
        guard let data = defaults.data(forKey: Self.patternsKey) else {
            cachedPatterns = []
            return
        }
        do {
            cachedPatterns = try decoder.decode([LoopInsightsCachedPattern].self, from: data)
        } catch {
            print("[LoopInsights] Failed to decode cached patterns: \(error)")
            cachedPatterns = []
        }
    }

    private func savePatterns() {
        do {
            let data = try encoder.encode(cachedPatterns)
            defaults.set(data, forKey: Self.patternsKey)
        } catch {
            print("[LoopInsights] Failed to encode cached patterns: \(error)")
        }
    }
}
