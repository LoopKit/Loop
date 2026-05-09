//
//  DataLayer_EventModels.swift
//  Loop
//
//  DataLayer — Event envelope, EventType enum, and all typed payloads.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

// MARK: - Event Envelope

/// Standard envelope wrapping every DataLayer event.
struct DataLayer_Event: Codable {
    let id: UUID
    let deviceID: String
    let eventType: DataLayer_EventType
    let timestamp: Date
    let sessionID: UUID
    let appVersion: String
    let schemaVersion: Int
    let payload: Data
    var uploadStatus: DataLayer_UploadStatus
    var uploadAttempts: Int
    let createdAt: Date
}

// MARK: - Upload Status

enum DataLayer_UploadStatus: String, Codable {
    case pending
    case uploading
    case uploaded
    case failed
    case redacted
}

// MARK: - Event Type (26 types)

enum DataLayer_EventType: String, Codable, CaseIterable {
    // Loop Core (polled)
    case glucoseSample
    case insulinDelivery
    case carbEntry

    // FoodFinder
    case mealAnalysis
    case mealConfirmed
    case barcodeScanned

    // BolusPro
    case bolusProEntry

    // LoopInsights — AI Suggestions
    case aiSuggestionGenerated
    case aiSuggestionApplied
    case aiSuggestionDismissed
    case aiSuggestionReverted

    // LoopInsights — Chat & Alerts
    case chatMessage
    case backgroundAlert

    // LoopInsights — Meal Debrief
    case mealDebrief

    // Substance Tracking
    case caffeineLogged
    case alcoholLogged

    // AutoPresets
    case presetActivated
    case presetDeactivated
    case activityDetected

    // Biometrics
    case biometricSnapshot

    // Settings & Overrides
    case therapySettingsChanged
    case overrideActivated
    case overrideDeactivated

    // Session
    case sessionStart
    case sessionEnd

    // GraphDetailView
    case graphDetailViewOpened

    // SiteAtlas
    case siteAtlasPlaced

    /// The consent category this event type belongs to.
    var consentCategory: DataLayer_ConsentCategory {
        switch self {
        case .glucoseSample:
            return .glucose
        case .insulinDelivery:
            return .insulin
        case .carbEntry, .mealAnalysis, .mealConfirmed, .barcodeScanned, .mealDebrief, .bolusProEntry:
            return .carbsAndMeals
        case .aiSuggestionGenerated, .aiSuggestionApplied, .aiSuggestionDismissed,
             .aiSuggestionReverted, .chatMessage, .backgroundAlert, .therapySettingsChanged:
            return .aiBehavioral
        case .biometricSnapshot:
            return .biometrics
        case .caffeineLogged, .alcoholLogged:
            return .substances
        case .presetActivated, .presetDeactivated, .activityDetected,
             .overrideActivated, .overrideDeactivated:
            return .activityAndPresets
        case .sessionStart, .sessionEnd:
            return .activityAndPresets
        case .graphDetailViewOpened, .siteAtlasPlaced:
            // Lightweight feature-usage signals; no glucose/insulin payload.
            return .activityAndPresets
        }
    }

    /// Current schema version for this event type.
    var currentSchemaVersion: Int { 1 }
}

// MARK: - Typed Payloads

/// Glucose sample batch payload.
struct DataLayer_GlucoseSamplePayload: Codable {
    let readings: [GlucoseReading]
    struct GlucoseReading: Codable {
        let timestamp: Date
        let mgdl: Double
        let trend: String?
    }
}

/// Insulin delivery batch payload.
struct DataLayer_InsulinDeliveryPayload: Codable {
    let deliveries: [Delivery]
    struct Delivery: Codable {
        let startDate: Date
        let endDate: Date
        let units: Double
        let type: String
        let isAutomatic: Bool
    }
}

/// Carb entry batch payload.
struct DataLayer_CarbEntryPayload: Codable {
    let entries: [Entry]
    struct Entry: Codable {
        let date: Date
        let grams: Double
        let absorptionTimeMinutes: Double?
        let foodType: String?
    }
}

/// Meal analysis payload (FoodFinder).
struct DataLayer_MealAnalysisPayload: Codable {
    let analysisType: String
    let foodName: String
    let carbsGrams: Double
    let originalAICarbs: Double?
    let aiConfidencePercent: Int?
    let proteinGrams: Double?
    let fatGrams: Double?
    let fiberGrams: Double?
    let calories: Double?
    let absorptionTimeHours: Double?
    let locationName: String?
    let itemCount: Int
}

/// Meal confirmed payload.
struct DataLayer_MealConfirmedPayload: Codable {
    let mealEventID: String
    let finalCarbsGrams: Double
    let carbDeltaFromAI: Double?
}

/// BolusPro entry payload — emitted once when a BolusPro-tagged carb entry
/// is saved alongside its primary, regardless of whether the user toggled
/// per-entry coverage on or off (so we can also study non-adoption).
///
/// All 12 fields are intentional: enough to fully reconstruct the dosing
/// decision at meal time and correlate with the existing Meal Debrief loop
/// 2 hours later.
struct DataLayer_BolusProPayload: Codable {
    /// Per-entry toggle state at submit time.
    let enabled: Bool
    /// Whether the toggle was flipped on by FoodFinder auto-detection (true)
    /// or by the user manually (false). nil when toggle was off.
    let autoDetected: Bool?
    /// Where the fat/protein values came from: `ai`, `product`, `favorite`,
    /// `manual`, or nil when no macros entered.
    let macrosSource: String?
    /// Strict-Warsaw kcal-based FPU score (1 FPU = 100 kcal).
    let fpuScore: Double
    /// Carb-equivalent grams written to the secondary entry (post-coverage).
    let bonusGrams: Double
    /// Slider position 0.0…1.0 at submit time. nil when toggle was off.
    let sliderPosition: Double?
    /// Per-user coverage knob in effect at submit time (10–100).
    let coverageFactorPercent: Int
    /// Configured FPU delay (0–120 min).
    let fpuDelayMinutes: Int
    /// Configured FPU absorption (4–8 h).
    let fpuAbsorptionHours: Int
    /// Raw fat input that drove the calculation, for reproducibility.
    let fatGramsInput: Double
    /// Raw protein input that drove the calculation, for reproducibility.
    let proteinGramsInput: Double
    /// Primary carb entry size at submit time, for ratio analysis.
    let primaryCarbGrams: Double
}

/// Barcode scanned payload.
struct DataLayer_BarcodeScannedPayload: Codable {
    let barcode: String
    let productName: String?
    let carbsGrams: Double?
    let source: String
    let found: Bool
}

/// AI suggestion payload (generated/applied/dismissed/reverted).
struct DataLayer_AISuggestionPayload: Codable {
    let settingType: String
    let timeBlockCount: Int
    let confidenceLevel: String
    let applyMode: String?
    let analysisPeriodDays: Int
}

/// Chat topic payload (topic only, never content).
struct DataLayer_ChatTopicPayload: Codable {
    let isVoiceInitiated: Bool
    let responseTimeSeconds: Double
    let topicCategory: String?
}

/// Caffeine logged payload.
struct DataLayer_CaffeineLoggedPayload: Codable {
    let milligrams: Double
    let source: String
    let currentLevelMg: Double
}

/// Alcohol logged payload.
struct DataLayer_AlcoholLoggedPayload: Codable {
    let standardDrinks: Double
    let source: String
    let currentLevel: Double
    let hypoRiskLevel: String
}

/// Preset activated/deactivated payload.
struct DataLayer_PresetEventPayload: Codable {
    let activityType: String
    let presetName: String
    let durationMinutes: Double?
}

/// Biometric snapshot payload.
struct DataLayer_BiometricSnapshotPayload: Codable {
    let periodHours: Int
    let avgHeartRate: Double?
    let avgHRV: Double?
    let totalSteps: Int?
    let sleepHours: Double?
    let activeCalories: Double?
    let weightKg: Double?
    let menstrualPhase: String?
}

/// Therapy settings changed payload.
struct DataLayer_TherapySettingsChangedPayload: Codable {
    let settingType: String
    let timeBlocksChanged: Int
    let wasAISuggested: Bool
    let source: String
}

/// Override activated/deactivated payload.
struct DataLayer_OverridePayload: Codable {
    let overrideType: String
    let presetName: String?
    let insulinNeedsScale: Double?
    let targetRangeLow: Double?
    let targetRangeHigh: Double?
}

/// Meal debrief payload.
struct DataLayer_MealDebriefPayload: Codable {
    let predictedPeakMgDl: Double?
    let actualPeakMgDl: Double?
    let effectiveCarbsEstimate: Double?
    let timeToPeakMinutes: Double?
    let learningCount: Int
}

/// Session start/end payload.
struct DataLayer_SessionPayload: Codable {
    let timezone: String
    let localeRegion: String?
}

/// GraphDetailView opened — fired when the long-press detail popup appears
/// on the glucose chart. Captures *what* data the user inspected so we can
/// learn which series users actually look at (signal beyond raw count).
struct DataLayer_GraphDetailViewOpenedPayload: Codable {
    let hasGlucose: Bool
    let hasIOB: Bool
    let hasCOB: Bool
    let hasBolus: Bool
    let hasBasalRate: Bool
    let hasPreset: Bool
    let hasAutoPreset: Bool
    let hasHeartRate: Bool
}

/// SiteAtlas site placed — fired when a user logs a new pump or sensor site.
/// Captures type + body side + zone so we can study placement preferences,
/// rotation discipline, and (later) outcome correlation.
struct DataLayer_SiteAtlasPlacedPayload: Codable {
    /// `"pump"` or `"sensor"`.
    let type: String
    /// `"front"` or `"back"`.
    let bodySide: String
    /// Recommended-zone identifier the placement falls inside, or nil if
    /// the user placed outside any recommended zone.
    let zoneID: String?
    /// True when the placement replaces a recently-hidden entry —
    /// signals churn / rapid replacement vs. fresh rotation.
    let replacementOfHidden: Bool
}
