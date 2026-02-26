//
//  DataLayer_ConsentModels.swift
//  Loop
//
//  DataLayer — Consent category enum and consent record model.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Consent Category

/// The 7 data categories users can individually consent to sharing.
enum DataLayer_ConsentCategory: String, Codable, CaseIterable, Identifiable {
    case glucose
    case insulin
    case carbsAndMeals
    case aiBehavioral
    case biometrics
    case substances
    case activityAndPresets

    var id: String { rawValue }

    /// User-facing display name for this category.
    var displayName: String {
        switch self {
        case .glucose:           return NSLocalizedString("Glucose", comment: "DataLayer consent category")
        case .insulin:           return NSLocalizedString("Insulin", comment: "DataLayer consent category")
        case .carbsAndMeals:     return NSLocalizedString("Carbs & Meals", comment: "DataLayer consent category")
        case .aiBehavioral:      return NSLocalizedString("AI & Behavioral", comment: "DataLayer consent category")
        case .biometrics:        return NSLocalizedString("Biometrics", comment: "DataLayer consent category")
        case .substances:        return NSLocalizedString("Substances", comment: "DataLayer consent category")
        case .activityAndPresets: return NSLocalizedString("Activity & Presets", comment: "DataLayer consent category")
        }
    }

    /// SF Symbol icon for this category.
    var iconName: String {
        switch self {
        case .glucose:           return "drop.fill"
        case .insulin:           return "syringe.fill"
        case .carbsAndMeals:     return "fork.knife"
        case .aiBehavioral:      return "brain.head.profile"
        case .biometrics:        return "heart.text.square"
        case .substances:        return "cup.and.saucer.fill"
        case .activityAndPresets: return "figure.run"
        }
    }

    /// Description of what data this category includes.
    var description: String {
        switch self {
        case .glucose:
            return NSLocalizedString("CGM glucose readings and trends", comment: "DataLayer glucose description")
        case .insulin:
            return NSLocalizedString("Insulin delivery data including basal, bolus, and automatic dosing", comment: "DataLayer insulin description")
        case .carbsAndMeals:
            return NSLocalizedString("Carb entries, meal analyses, barcode scans, and meal debriefs", comment: "DataLayer carbs description")
        case .aiBehavioral:
            return NSLocalizedString("AI suggestion history, chat topics, alerts, and settings changes", comment: "DataLayer AI description")
        case .biometrics:
            return NSLocalizedString("Heart rate, HRV, steps, sleep, active energy, and weight", comment: "DataLayer biometrics description")
        case .substances:
            return NSLocalizedString("Caffeine and alcohol intake logs", comment: "DataLayer substances description")
        case .activityAndPresets:
            return NSLocalizedString("Activity detection, preset activations, and override usage", comment: "DataLayer activity description")
        }
    }
}

// MARK: - Consent Record

/// A timestamped record of a consent change for audit trail.
struct DataLayer_ConsentRecord: Codable, Identifiable {
    let id: UUID
    let category: DataLayer_ConsentCategory
    let granted: Bool
    let timestamp: Date

    init(category: DataLayer_ConsentCategory, granted: Bool) {
        self.id = UUID()
        self.category = category
        self.granted = granted
        self.timestamp = Date()
    }
}
