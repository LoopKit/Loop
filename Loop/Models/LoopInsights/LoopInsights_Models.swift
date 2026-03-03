//
//  LoopInsights_Models.swift
//  Loop
//
//  Concept & design by Taylor Patterson. Coded & tested by Claude Code in February 2026.
//  Copyright (c) 2025-2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

// MARK: - Setting Type

/// The three therapy settings LoopInsights can analyze and suggest changes for
enum LoopInsightsSettingType: String, Codable, CaseIterable, Identifiable {
    case basalRate = "basal_rate"
    case carbRatio = "carb_ratio"
    case insulinSensitivity = "insulin_sensitivity"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .carbRatio:
            return NSLocalizedString("Carb Ratio", comment: "LoopInsights setting type: Carb Ratio")
        case .insulinSensitivity:
            return NSLocalizedString("Insulin Sensitivity", comment: "LoopInsights setting type: Insulin Sensitivity Factor")
        case .basalRate:
            return NSLocalizedString("Basal Rate", comment: "LoopInsights setting type: Basal Rate")
        }
    }

    var abbreviation: String {
        switch self {
        case .carbRatio: return "CR"
        case .insulinSensitivity: return "ISF"
        case .basalRate: return "BR"
        }
    }

    var unitDescription: String {
        switch self {
        case .carbRatio:
            return NSLocalizedString("g/U", comment: "LoopInsights unit: grams per unit of insulin")
        case .insulinSensitivity:
            return NSLocalizedString("mg/dL per U", comment: "LoopInsights unit: mg/dL per unit of insulin")
        case .basalRate:
            return NSLocalizedString("U/hr", comment: "LoopInsights unit: units per hour")
        }
    }

    var systemImage: String {
        switch self {
        case .carbRatio: return "fork.knife"
        case .insulinSensitivity: return "arrow.up.arrow.down"
        case .basalRate: return "drop.fill"
        }
    }

    /// Snaps a value to the nearest valid Loop therapy setting increment.
    func roundedToIncrement(_ value: Double) -> Double {
        switch self {
        case .carbRatio:          return (value * 10).rounded() / 10   // 0.1 increments
        case .basalRate:          return (value * 20).rounded() / 20   // 0.05 increments
        case .insulinSensitivity: return value.rounded()               // whole numbers
        }
    }

    /// Format string appropriate for this setting type's display increment.
    var valueFormatString: String {
        switch self {
        case .carbRatio:          return "%.1f"
        case .basalRate:          return "%.2f"
        case .insulinSensitivity: return "%.0f"
        }
    }
}

// MARK: - Setting Analysis Status

/// Status of an individual therapy setting after analysis
enum LoopInsightsSettingStatus {
    case notAnalyzed      // Gray — hasn't been analyzed yet
    case analyzedOK       // Green — analyzed, no changes needed
    case hasSuggestions   // Orange — has pending suggestions
}

// MARK: - Safety Guardrails

/// Absolute and recommended clinical bounds for therapy settings.
/// Mirrors LoopKit's `Guardrail+Settings.swift` as self-contained constants
/// so LoopInsights can validate without importing LoopKit guardrail types.
struct LoopInsights_SafetyGuardrails {

    /// Classification of a value relative to guardrail bounds
    enum Classification {
        case withinRecommended
        case belowRecommended
        case aboveRecommended
        case belowAbsolute
        case aboveAbsolute
    }

    // -- Carb Ratio (g/U) --
    static let crRecommendedMin: Double = 4.0
    static let crRecommendedMax: Double = 28.0
    static let crAbsoluteMin: Double = 2.0
    static let crAbsoluteMax: Double = 150.0

    // -- Insulin Sensitivity Factor (mg/dL per U) --
    static let isfRecommendedMin: Double = 16.0
    static let isfRecommendedMax: Double = 400.0
    static let isfAbsoluteMin: Double = 10.0
    static let isfAbsoluteMax: Double = 500.0

    // -- Basal Rate (U/hr) --
    static let basalRecommendedMin: Double = 0.05
    static let basalRecommendedMax: Double = 10.0
    static let basalAbsoluteMin: Double = 0.05
    static let basalAbsoluteMax: Double = 30.0

    /// Maximum allowed percentage change per analysis step (backstop)
    static let maxChangePercent: Double = 25.0

    /// Stricter limit for basal rate — basal delivers insulin continuously (including overnight)
    /// so changes compound over hours and carry higher hypoglycemia risk than CR or ISF changes.
    static let maxBasalChangePercent: Double = 15.0

    /// Classify a value against the guardrail bounds for a setting type
    static func classify(value: Double, settingType: LoopInsightsSettingType) -> Classification {
        let (recMin, recMax, absMin, absMax) = bounds(for: settingType)

        if value < absMin { return .belowAbsolute }
        if value > absMax { return .aboveAbsolute }
        if value < recMin { return .belowRecommended }
        if value > recMax { return .aboveRecommended }
        return .withinRecommended
    }

    /// Human-readable warning string, or nil if value is within recommended range
    static func warningMessage(value: Double, settingType: LoopInsightsSettingType) -> String? {
        let classification = classify(value: value, settingType: settingType)
        let (recMin, recMax, absMin, absMax) = bounds(for: settingType)
        let unit = settingType.unitDescription
        let name = settingType.displayName

        switch classification {
        case .withinRecommended:
            return nil
        case .belowAbsolute:
            return String(
                format: NSLocalizedString(
                    "%@ value %.1f %@ is below the absolute minimum (%.1f %@). This value cannot be applied.",
                    comment: "LoopInsights guardrail: below absolute"
                ),
                name, value, unit, absMin, unit
            )
        case .aboveAbsolute:
            return String(
                format: NSLocalizedString(
                    "%@ value %.1f %@ exceeds the absolute maximum (%.1f %@). This value cannot be applied.",
                    comment: "LoopInsights guardrail: above absolute"
                ),
                name, value, unit, absMax, unit
            )
        case .belowRecommended:
            return String(
                format: NSLocalizedString(
                    "%@ value %.1f %@ is below the recommended minimum (%.1f %@). Consult your healthcare provider before applying.",
                    comment: "LoopInsights guardrail: below recommended"
                ),
                name, value, unit, recMin, unit
            )
        case .aboveRecommended:
            return String(
                format: NSLocalizedString(
                    "%@ value %.1f %@ exceeds the recommended maximum (%.1f %@). Consult your healthcare provider before applying.",
                    comment: "LoopInsights guardrail: above recommended"
                ),
                name, value, unit, recMax, unit
            )
        }
    }

    /// Returns (recommendedMin, recommendedMax, absoluteMin, absoluteMax) for a setting type
    private static func bounds(for settingType: LoopInsightsSettingType) -> (Double, Double, Double, Double) {
        switch settingType {
        case .carbRatio:
            return (crRecommendedMin, crRecommendedMax, crAbsoluteMin, crAbsoluteMax)
        case .insulinSensitivity:
            return (isfRecommendedMin, isfRecommendedMax, isfAbsoluteMin, isfAbsoluteMax)
        case .basalRate:
            return (basalRecommendedMin, basalRecommendedMax, basalAbsoluteMin, basalAbsoluteMax)
        }
    }
}

// MARK: - Detected Pattern

/// A glucose/insulin pattern detected from aggregated data
struct LoopInsightsDetectedPattern: Identifiable {
    let id = UUID()
    let type: LoopInsightsPatternType
    let detail: String
    let severity: LoopInsightsConfidence
}

/// Types of patterns LoopInsights can detect from glucose/insulin/carb data
enum LoopInsightsPatternType: String, CaseIterable {
    case overnightLows
    case frequentLows
    case overnightHighs
    case dawnPhenomenon
    case postMealSpikes
    case reboundHighs
    case highVariability
    case consistentHighs
    case consistentLows
    case negativeBasal
    case highStress
    case caffeineCorrelation
    case foodSensitivity

    var displayName: String {
        switch self {
        case .overnightLows:
            return NSLocalizedString("Overnight Lows", comment: "LoopInsights pattern: overnight lows")
        case .frequentLows:
            return NSLocalizedString("Frequent Lows", comment: "LoopInsights pattern: frequent lows")
        case .overnightHighs:
            return NSLocalizedString("Overnight Highs", comment: "LoopInsights pattern: overnight highs")
        case .dawnPhenomenon:
            return NSLocalizedString("Dawn Phenomenon", comment: "LoopInsights pattern: dawn phenomenon")
        case .postMealSpikes:
            return NSLocalizedString("Post-Meal Spikes", comment: "LoopInsights pattern: post-meal spikes")
        case .reboundHighs:
            return NSLocalizedString("Rebound Highs", comment: "LoopInsights pattern: rebound highs")
        case .highVariability:
            return NSLocalizedString("High Variability", comment: "LoopInsights pattern: high variability")
        case .consistentHighs:
            return NSLocalizedString("Consistent Highs", comment: "LoopInsights pattern: consistent highs")
        case .consistentLows:
            return NSLocalizedString("Consistent Lows", comment: "LoopInsights pattern: consistent lows")
        case .negativeBasal:
            return NSLocalizedString("Frequent Suspensions", comment: "LoopInsights pattern: negative basal")
        case .highStress:
            return NSLocalizedString("High Stress Periods", comment: "LoopInsights pattern: high stress")
        case .caffeineCorrelation:
            return NSLocalizedString("Caffeine Impact", comment: "LoopInsights pattern: caffeine correlation")
        case .foodSensitivity:
            return NSLocalizedString("Food Sensitivity", comment: "LoopInsights pattern: food sensitivity")
        }
    }

    var systemImage: String {
        switch self {
        case .overnightLows: return "moon.zzz"
        case .frequentLows: return "arrow.down.circle"
        case .overnightHighs: return "moon.stars"
        case .dawnPhenomenon: return "sunrise"
        case .postMealSpikes: return "fork.knife"
        case .reboundHighs: return "arrow.turn.up.right"
        case .highVariability: return "waveform.path.ecg"
        case .consistentHighs: return "arrow.up.circle"
        case .consistentLows: return "arrow.down.to.line"
        case .negativeBasal: return "pause.circle"
        case .highStress: return "brain.head.profile"
        case .caffeineCorrelation: return "cup.and.saucer.fill"
        case .foodSensitivity: return "fork.knife"
        }
    }
}

// MARK: - Analysis Period

/// How far back LoopInsights looks when aggregating data
enum LoopInsightsAnalysisPeriod: Int, Codable, CaseIterable, Identifiable {
    case threeDays = 3
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .threeDays:
            return NSLocalizedString("3 Days", comment: "LoopInsights analysis period: 3 days")
        case .sevenDays:
            return NSLocalizedString("7 Days", comment: "LoopInsights analysis period: 7 days")
        case .fourteenDays:
            return NSLocalizedString("14 Days", comment: "LoopInsights analysis period: 14 days")
        case .thirtyDays:
            return NSLocalizedString("30 Days", comment: "LoopInsights analysis period: 30 days")
        case .ninetyDays:
            return NSLocalizedString("90 Days", comment: "LoopInsights analysis period: 90 days")
        }
    }

    var timeInterval: TimeInterval {
        return TimeInterval(rawValue) * 24 * 60 * 60
    }
}

// MARK: - AI Personality

/// Personality style for AI responses — changes the tone of assessments and reasoning
enum LoopInsightsAIPersonality: String, Codable, CaseIterable, Identifiable {
    case supportiveCoach = "supportive_coach"
    case clinicalExpert = "clinical_expert"
    case dryWit = "dry_wit"
    case toughLove = "tough_love"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .supportiveCoach:
            return NSLocalizedString("Supportive Coach", comment: "LoopInsights personality: supportive coach")
        case .clinicalExpert:
            return NSLocalizedString("Clinical Expert", comment: "LoopInsights personality: clinical expert")
        case .dryWit:
            return NSLocalizedString("Dry Wit", comment: "LoopInsights personality: dry wit")
        case .toughLove:
            return NSLocalizedString("Tough Love", comment: "LoopInsights personality: tough love")
        }
    }

    var description: String {
        switch self {
        case .supportiveCoach:
            return NSLocalizedString("Encouraging and positive. Celebrates your wins and gently explains areas for improvement.", comment: "LoopInsights personality desc: supportive coach")
        case .clinicalExpert:
            return NSLocalizedString("Professional and evidence-based. Precise medical terminology with clear clinical reasoning.", comment: "LoopInsights personality desc: clinical expert")
        case .dryWit:
            return NSLocalizedString("Witty and clever. No sugar-coating (pun intended) — helpful advice with a side of humor.", comment: "LoopInsights personality desc: dry wit")
        case .toughLove:
            return NSLocalizedString("Direct and no-nonsense. Holds you accountable and tells it like it is.", comment: "LoopInsights personality desc: tough love")
        }
    }

    /// Prompt instructions injected into the AI system prompt
    var promptInstruction: String {
        switch self {
        case .supportiveCoach:
            return """
            PERSONALITY: You are a warm, encouraging diabetes coach. Celebrate what's going well before \
            discussing changes. Use phrases like "Great job on...", "Let's work together to...", and \
            "You're making real progress with...". Be optimistic and supportive while still being honest \
            about areas that need attention. Use simple, accessible language.
            """
        case .clinicalExpert:
            return """
            PERSONALITY: You are a board-certified endocrinologist reviewing pump settings. Use precise \
            medical terminology (TIR, CV, GMI, basal/bolus ratio). Reference clinical guidelines (ADA, \
            consensus targets) when making recommendations. Be thorough, methodical, and evidence-based. \
            Maintain a professional, measured tone throughout.
            """
        case .dryWit:
            return """
            PERSONALITY: You are a witty diabetes advisor with a dry sense of humor. Deliver helpful, \
            accurate advice but make it entertaining. Use clever wordplay, diabetes-related puns, and \
            wry observations. You might say things like "Your overnight basals are throwing a party \
            your glucose wasn't invited to" or "That dawn phenomenon is more reliable than your alarm \
            clock." Always be helpful underneath the humor.
            """
        case .toughLove:
            return """
            PERSONALITY: You are a brutally honest drill-sergeant-style diabetes coach. You do NOT \
            hand out participation trophies. Lead with what's wrong — skip the pleasantries. Use \
            blunt, punchy language: "These numbers are unacceptable", "You're leaving 20% TIR on \
            the table and that's on your settings", "Stop ignoring this — your overnights are a \
            mess." If a pattern is dangerous, say so plainly: "This is putting you at risk. Full \
            stop." Be relentless about accountability — if the data shows a problem, hammer it home. \
            Every statement should hit hard, but always end with a concrete fix. You're tough because \
            you care, not because you're cruel.
            """
        }
    }
}

// MARK: - Apply Mode

/// How suggestions are applied to therapy settings
enum LoopInsightsApplyMode: String, Codable, CaseIterable, Identifiable {
    case manual = "manual"
    case oneTap = "one_tap"
    case preFill = "pre_fill"
    case autoApply = "auto_apply"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return NSLocalizedString("Manual", comment: "LoopInsights apply mode: navigate to settings manually")
        case .oneTap:
            return NSLocalizedString("One-Tap Apply", comment: "LoopInsights apply mode: apply with confirmation")
        case .preFill:
            return NSLocalizedString("Pre-Fill Editor", comment: "LoopInsights apply mode: navigate to editor with value pre-filled")
        case .autoApply:
            return NSLocalizedString("Auto-Apply", comment: "LoopInsights apply mode: automatically apply suggestions (developer only)")
        }
    }

    var description: String {
        switch self {
        case .manual:
            return NSLocalizedString("View the suggested values, then navigate to Therapy Settings to make changes yourself.", comment: "LoopInsights apply mode description: manual")
        case .oneTap:
            return NSLocalizedString("Apply suggestions with a single tap. You'll see a confirmation with a responsibility disclaimer.", comment: "LoopInsights apply mode description: one-tap")
        case .preFill:
            return NSLocalizedString("Opens the Therapy Settings editor with the suggested value pre-filled. You confirm by tapping Save.", comment: "LoopInsights apply mode description: pre-fill")
        case .autoApply:
            return NSLocalizedString("Suggestions are applied automatically when confidence is high. All changes are logged.", comment: "LoopInsights apply mode description: auto-apply")
        }
    }

    /// Modes visible to all users (auto-apply is developer-only)
    static var publicModes: [LoopInsightsApplyMode] {
        return [.manual, .oneTap, .preFill]
    }
}

// MARK: - Request Format

/// Determines how the HTTP request body is built and how the response is parsed.
/// Supports OpenAI-compatible endpoints (OpenAI, Azure, Groq, Together, Ollama, etc.),
/// Anthropic Messages API, and Google Generative AI (Gemini).
enum LoopInsightsRequestFormat: String, Codable, CaseIterable, Equatable {
    case openAICompatible
    case anthropicMessages
    case googleGenerativeAI

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropicMessages: return "Anthropic Messages"
        case .googleGenerativeAI: return "Google Generative AI"
        }
    }

    /// Default response JSON path for extracting text content.
    var defaultResponseKeyPath: String {
        switch self {
        case .openAICompatible: return "choices.0.message.content"
        case .anthropicMessages: return "content.0.text"
        case .googleGenerativeAI: return "candidates.0.content.parts.0.text"
        }
    }

    /// Default API key header name.
    var defaultAPIKeyHeader: String {
        switch self {
        case .openAICompatible: return "Authorization"
        case .anthropicMessages: return "x-api-key"
        case .googleGenerativeAI: return "x-goog-api-key"
        }
    }

    /// Default API key prefix (e.g., "Bearer " for OpenAI).
    var defaultAPIKeyPrefix: String {
        switch self {
        case .openAICompatible: return "Bearer "
        case .anthropicMessages: return ""
        case .googleGenerativeAI: return ""
        }
    }

    /// Default endpoint path.
    var defaultEndpoint: String {
        switch self {
        case .openAICompatible: return "/chat/completions"
        case .anthropicMessages: return "/messages"
        case .googleGenerativeAI: return "/models/{MODEL}:generateContent"
        }
    }

    /// Auto-detect request format from a base URL.
    /// Falls back to `.openAICompatible` for any unrecognized URL.
    static func detect(from baseURL: String) -> LoopInsightsRequestFormat {
        let lower = baseURL.lowercased()
        if lower.contains("anthropic.com") {
            return .anthropicMessages
        } else if lower.contains("googleapis.com") || lower.contains("generativelanguage") {
            return .googleGenerativeAI
        }
        return .openAICompatible
    }
}

// MARK: - AI Provider Configuration

/// User-configurable AI endpoint configuration for LoopInsights.
///
/// The `apiKey` field is populated at runtime from the Keychain and is NOT
/// persisted to UserDefaults. Use `LoopInsights_SecureStorage` to read/write keys.
struct LoopInsightsAIProviderConfiguration: Codable, Equatable {
    var baseURL: String
    var model: String
    var endpointPath: String
    var requestFormat: LoopInsightsRequestFormat
    var apiKeyHeader: String
    var apiKeyPrefix: String
    var maxTokens: Int
    var temperature: Double
    var apiVersion: String?
    var organizationID: String?

    /// Transient — populated from Keychain at load time, NOT stored in UserDefaults.
    var apiKey: String

    init(
        baseURL: String = "https://api.openai.com/v1",
        model: String = "gpt-4o",
        endpointPath: String? = nil,
        requestFormat: LoopInsightsRequestFormat = .openAICompatible,
        apiKeyHeader: String? = nil,
        apiKeyPrefix: String? = nil,
        maxTokens: Int = 2048,
        temperature: Double = 0.0,
        apiVersion: String? = nil,
        organizationID: String? = nil,
        apiKey: String = ""
    ) {
        self.baseURL = baseURL
        self.model = model
        self.endpointPath = endpointPath ?? requestFormat.defaultEndpoint
        self.requestFormat = requestFormat
        self.apiKeyHeader = apiKeyHeader ?? requestFormat.defaultAPIKeyHeader
        self.apiKeyPrefix = apiKeyPrefix ?? requestFormat.defaultAPIKeyPrefix
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.apiVersion = apiVersion
        self.organizationID = organizationID
        self.apiKey = apiKey
    }

    /// Returns a copy with the API key loaded from Keychain.
    func withKeychainAPIKey() -> LoopInsightsAIProviderConfiguration {
        var copy = self
        copy.apiKey = LoopInsights_SecureStorage.loadAPIKey() ?? ""
        return copy
    }

    // MARK: - Codable (exclude apiKey from persistence)

    enum CodingKeys: String, CodingKey {
        case baseURL, model, endpointPath, requestFormat
        case apiKeyHeader, apiKeyPrefix, maxTokens, temperature
        case apiVersion, organizationID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        endpointPath = try c.decode(String.self, forKey: .endpointPath)
        requestFormat = try c.decode(LoopInsightsRequestFormat.self, forKey: .requestFormat)
        apiKeyHeader = try c.decode(String.self, forKey: .apiKeyHeader)
        apiKeyPrefix = try c.decode(String.self, forKey: .apiKeyPrefix)
        maxTokens = try c.decode(Int.self, forKey: .maxTokens)
        temperature = try c.decode(Double.self, forKey: .temperature)
        apiVersion = try c.decodeIfPresent(String.self, forKey: .apiVersion)
        organizationID = try c.decodeIfPresent(String.self, forKey: .organizationID)
        apiKey = "" // Never decoded — loaded from Keychain
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(model, forKey: .model)
        try c.encode(endpointPath, forKey: .endpointPath)
        try c.encode(requestFormat, forKey: .requestFormat)
        try c.encode(apiKeyHeader, forKey: .apiKeyHeader)
        try c.encode(apiKeyPrefix, forKey: .apiKeyPrefix)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(temperature, forKey: .temperature)
        try c.encodeIfPresent(apiVersion, forKey: .apiVersion)
        try c.encodeIfPresent(organizationID, forKey: .organizationID)
        // apiKey intentionally omitted — stored in Keychain only
    }
}

// MARK: - Confidence Level

/// How confident the AI is in a suggestion
enum LoopInsightsConfidence: String, Codable, Comparable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayName: String {
        switch self {
        case .low:
            return NSLocalizedString("Low", comment: "LoopInsights confidence: low")
        case .medium:
            return NSLocalizedString("Medium", comment: "LoopInsights confidence: medium")
        case .high:
            return NSLocalizedString("High", comment: "LoopInsights confidence: high")
        }
    }

    var color: String {
        switch self {
        case .low: return "yellow"
        case .medium: return "orange"
        case .high: return "blue"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: LoopInsightsConfidence, rhs: LoopInsightsConfidence) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Time Block

/// A specific time block within a schedule (e.g., 12pm-3pm)
struct LoopInsightsTimeBlock: Codable, Identifiable, Equatable {
    let id: UUID
    let startTime: TimeInterval  // Seconds since midnight
    let endTime: TimeInterval    // Seconds since midnight
    let currentValue: Double
    let proposedValue: Double

    init(startTime: TimeInterval, endTime: TimeInterval, currentValue: Double, proposedValue: Double) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.currentValue = currentValue
        self.proposedValue = proposedValue
    }

    var startTimeFormatted: String {
        return Self.formatTime(startTime)
    }

    var endTimeFormatted: String {
        return Self.formatTime(endTime)
    }

    var timeRangeFormatted: String {
        return "\(startTimeFormatted) – \(endTimeFormatted)"
    }

    var changePercent: Double {
        guard currentValue != 0 else { return 0 }
        return ((proposedValue - currentValue) / currentValue) * 100
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static func formatTime(_ seconds: TimeInterval) -> String {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let date = calendar.startOfDay(for: Date()).addingTimeInterval(seconds)
        return timeFormatter.string(from: date)
    }
}

// MARK: - Suggestion

/// A single AI-generated therapy setting suggestion
struct LoopInsightsSuggestion: Codable, Identifiable, Equatable {
    let id: UUID
    let settingType: LoopInsightsSettingType
    let timeBlocks: [LoopInsightsTimeBlock]
    let reasoning: String
    let confidence: LoopInsightsConfidence
    let analysisPeriod: LoopInsightsAnalysisPeriod
    let createdAt: Date

    /// Summary of the overall change direction
    var summaryDescription: String {
        guard let first = timeBlocks.first else {
            return NSLocalizedString("No changes suggested", comment: "LoopInsights: no suggestion")
        }

        if timeBlocks.count == 1 {
            let direction = first.proposedValue > first.currentValue
                ? NSLocalizedString("Increase", comment: "LoopInsights: increase direction")
                : NSLocalizedString("Decrease", comment: "LoopInsights: decrease direction")
            return "\(direction) \(settingType.abbreviation) at \(first.timeRangeFormatted)"
        } else {
            return String(
                format: NSLocalizedString("Adjust %@ across %d time blocks", comment: "LoopInsights: multi-block suggestion summary"),
                settingType.abbreviation,
                timeBlocks.count
            )
        }
    }

    // MARK: - Guardrail Computed Properties

    /// Warning strings for any proposed values outside recommended bounds
    var guardrailWarnings: [String] {
        timeBlocks.compactMap { block in
            LoopInsights_SafetyGuardrails.warningMessage(value: block.proposedValue, settingType: settingType)
        }
    }

    /// True if any proposed value falls outside the recommended range
    var hasGuardrailWarning: Bool {
        timeBlocks.contains { block in
            let c = LoopInsights_SafetyGuardrails.classify(value: block.proposedValue, settingType: settingType)
            return c != .withinRecommended
        }
    }

    /// True if any proposed value falls outside the absolute bounds (hard block)
    var hasAbsoluteViolation: Bool {
        timeBlocks.contains { block in
            let c = LoopInsights_SafetyGuardrails.classify(value: block.proposedValue, settingType: settingType)
            return c == .belowAbsolute || c == .aboveAbsolute
        }
    }

    static func == (lhs: LoopInsightsSuggestion, rhs: LoopInsightsSuggestion) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Therapy Snapshot

/// A point-in-time capture of all therapy settings, used for before/after comparison
struct LoopInsightsTherapySnapshot: Codable {
    let basalRateItems: [LoopInsightsScheduleItem]
    let insulinSensitivityItems: [LoopInsightsScheduleItem]
    let carbRatioItems: [LoopInsightsScheduleItem]
    let insulinTypeName: String?
    let insulinDiaHours: Double?  // Duration of Insulin Action in hours (from insulin model)
    let capturedAt: Date

    struct LoopInsightsScheduleItem: Codable, Identifiable {
        let id: UUID
        let startTime: TimeInterval  // Seconds since midnight
        let value: Double

        init(startTime: TimeInterval, value: Double) {
            self.id = UUID()
            self.startTime = startTime
            self.value = value
        }
    }
}

// MARK: - Aggregated Stats

/// Aggregated statistics from Loop's data stores, used as input to AI analysis
struct LoopInsightsAggregatedStats: Codable {
    let period: LoopInsightsAnalysisPeriod
    let glucoseStats: GlucoseStats
    let insulinStats: InsulinStats
    let carbStats: CarbStats
    let biometricStats: BiometricStats?
    let generatedAt: Date

    struct GlucoseStats: Codable {
        let averageGlucose: Double           // mg/dL
        let standardDeviation: Double         // mg/dL
        let coefficientOfVariation: Double    // percentage
        let timeInRange: Double               // percentage (70-180 mg/dL)
        let timeInTightRange: Double          // percentage (70-tightRangeUpperBound mg/dL)
        let tightRangeUpperBound: Int         // configured upper bound for tight range
        let timeVeryHigh: Double              // percentage (>250 mg/dL)
        let timeHigh: Double                  // percentage (181-250 mg/dL)
        let timeLow: Double                   // percentage (54-69 mg/dL)
        let timeVeryLow: Double               // percentage (<54 mg/dL)
        let gmi: Double                       // Glucose Management Indicator (estimated A1C)
        let sampleCount: Int
        let hourlyAverages: [Int: Double]     // hour (0-23) → average glucose

        /// Combined time below range (<70 mg/dL) — timeLow + timeVeryLow
        var timeBelowRange: Double { timeLow + timeVeryLow }
        /// Combined time above range (>180 mg/dL) — timeHigh + timeVeryHigh
        var timeAboveRange: Double { timeHigh + timeVeryHigh }
    }

    struct DailyInsulinBreakdown: Codable {
        let date: Date
        let totalDailyDose: Double            // total units delivered that day
        let basalUnits: Double
        let bolusUnits: Double
    }

    struct InsulinStats: Codable {
        let totalDailyDose: Double            // Average total units/day
        let basalPercentage: Double           // percentage of TDD from basal
        let bolusPercentage: Double           // percentage of TDD from bolus
        let hourlyBasalAverages: [Int: Double] // hour → average basal rate delivered
        let correctionBolusCount: Int         // number of correction boluses in period
        let negativeBasalStats: LoopInsightsNegativeBasalStats?  // Phase 5: suspension/sub-basal stats

        // TDI tracking
        let dailyBreakdown: [DailyInsulinBreakdown]  // per-day TDD for trending
        let tddMin: Double                   // minimum single-day TDD in period
        let tddMax: Double                   // maximum single-day TDD in period
        let tddVariabilityCV: Double         // coefficient of variation of daily TDD (%)
        let tddWeekOverWeekChange: Double?   // % change comparing recent 7d vs prior 7d (nil if <14 days)
    }

    struct CarbStats: Codable {
        let averageDailyCarbs: Double         // grams/day
        let mealCount: Int                    // total meals logged
        let averageCarbsPerMeal: Double       // grams/meal
        let hourlyMealFrequency: [Int: Int]   // hour → number of meals at that hour
    }

    struct BiometricStats: Codable {
        let heartRate: HeartRateStats?
        let hrv: HRVStats?
        let steps: StepStats?
        let sleep: SleepStats?
        let activeEnergy: ActiveEnergyStats?
        let weight: WeightStats?
        let stressScore: LoopInsightsStressScore?  // Phase 5: HRV-derived stress
        let menstrualCycle: LoopInsightsMenstrualCycleStats?  // Phase 5: hormonal context
    }

    struct HeartRateStats: Codable {
        let averageRestingHR: Double          // bpm
        let averageActiveHR: Double           // bpm
        let hourlyAverages: [Int: Double]     // hour → avg bpm
    }

    struct HRVStats: Codable {
        let averageSDNN: Double               // ms
        let trend: Double                     // positive = improving
    }

    struct StepStats: Codable {
        let averageDailySteps: Double
        let hourlyAverages: [Int: Double]     // hour → avg steps
    }

    struct SleepStats: Codable {
        let averageDurationHours: Double
        let averageBedtime: Double            // seconds since midnight
        let averageWakeTime: Double           // seconds since midnight
    }

    struct ActiveEnergyStats: Codable {
        let averageDailyCalories: Double
        let hourlyAverages: [Int: Double]     // hour → avg kcal burned
    }

    struct WeightStats: Codable {
        let latestWeight: Double              // kg
        let weightTrend: Double               // kg change over period
    }
}

// MARK: - AI Analysis Request/Response

/// The structured request sent to the AI provider
struct LoopInsightsAnalysisRequest: Codable {
    let currentSettings: LoopInsightsTherapySnapshot
    let aggregatedStats: LoopInsightsAggregatedStats
    let focusSettingType: LoopInsightsSettingType
    let userNotes: String?
}

/// The structured response parsed from the AI provider
struct LoopInsightsAnalysisResponse: Codable {
    let suggestions: [LoopInsightsSuggestion]
    let overallAssessment: String
    let nextRecommendedFocus: LoopInsightsSettingType?
    let rawResponse: String?
}

// MARK: - Error Types

enum LoopInsightsError: Error, LocalizedError {
    case noAPIKeyConfigured
    case aiProviderError(String)
    case networkError(Error)
    case parseError(String)
    case insufficientData(String)
    case settingsWriteError(String)
    case keychainError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKeyConfigured:
            return NSLocalizedString("No API key configured. Please add your API key in LoopInsights Settings.", comment: "LoopInsights error: no API key")
        case .aiProviderError(let message):
            return String(format: NSLocalizedString("AI Provider Error: %@", comment: "LoopInsights error: AI provider"), message)
        case .networkError(let error):
            return String(format: NSLocalizedString("Network Error: %@", comment: "LoopInsights error: network"), error.localizedDescription)
        case .parseError(let message):
            return String(format: NSLocalizedString("Failed to parse AI response: %@", comment: "LoopInsights error: parse"), message)
        case .insufficientData(let message):
            return String(format: NSLocalizedString("Insufficient data for analysis: %@", comment: "LoopInsights error: insufficient data"), message)
        case .settingsWriteError(let message):
            return String(format: NSLocalizedString("Failed to apply settings: %@", comment: "LoopInsights error: settings write"), message)
        case .keychainError(let message):
            return String(format: NSLocalizedString("Keychain Error: %@", comment: "LoopInsights error: keychain"), message)
        }
    }
}

// MARK: - Monitor Frequency

/// How often the background monitor runs AI analysis
enum LoopInsightsMonitorFrequency: String, Codable, CaseIterable, Identifiable {
    case sixHours = "six_hours"
    case twelveHours = "twelve_hours"
    case daily = "daily"
    case weekly = "weekly"

    var id: String { rawValue }

    var timeInterval: TimeInterval {
        switch self {
        case .sixHours: return 6 * 3600
        case .twelveHours: return 12 * 3600
        case .daily: return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        }
    }

    var displayName: String {
        switch self {
        case .sixHours:
            return NSLocalizedString("Every 6 Hours", comment: "LoopInsights monitor frequency: 6 hours")
        case .twelveHours:
            return NSLocalizedString("Every 12 Hours", comment: "LoopInsights monitor frequency: 12 hours")
        case .daily:
            return NSLocalizedString("Once Daily", comment: "LoopInsights monitor frequency: daily")
        case .weekly:
            return NSLocalizedString("Once Weekly", comment: "LoopInsights monitor frequency: weekly")
        }
    }
}

// MARK: - Notification Style

/// How the background monitor delivers notifications
enum LoopInsightsNotificationStyle: String, Codable, CaseIterable, Identifiable {
    case banner
    case push
    case silent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .banner:
            return NSLocalizedString("In-App Banner", comment: "LoopInsights notification style: banner")
        case .push:
            return NSLocalizedString("Push Notification", comment: "LoopInsights notification style: push")
        case .silent:
            return NSLocalizedString("Silent (Badge Only)", comment: "LoopInsights notification style: silent")
        }
    }

    var description: String {
        switch self {
        case .banner:
            return NSLocalizedString("Shows a banner inside the app when a new suggestion is found.", comment: "LoopInsights notification style desc: banner")
        case .push:
            return NSLocalizedString("Sends a push notification even when the app is in the background.", comment: "LoopInsights notification style desc: push")
        case .silent:
            return NSLocalizedString("No alert — suggestions are available when you next open LoopInsights.", comment: "LoopInsights notification style desc: silent")
        }
    }
}

// MARK: - Debug Log

/// Captures the full prompt/response exchange for a single AI analysis call.
/// Used in developer mode to inspect what's being sent to the AI provider.
struct LoopInsightsDebugLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let settingType: LoopInsightsSettingType
    let systemPrompt: String
    let userPrompt: String
    let rawResponse: String
}

// MARK: - Chat Message

/// A single message in a LoopInsights chat conversation
struct LoopInsightsChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let voiceInitiated: Bool

    enum Role: String {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String, voiceInitiated: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.voiceInitiated = voiceInitiated
    }
}

// MARK: - Chat Session

/// Manages an in-memory chat session. Conversations are not persisted
/// across app launches — the AI always starts fresh with current data context.
final class LoopInsightsChatSession: ObservableObject {
    @Published private(set) var messages: [LoopInsightsChatMessage] = []
    let sessionStarted: Date

    init() {
        self.sessionStarted = Date()
    }

    func appendMessage(_ message: LoopInsightsChatMessage) {
        messages.append(message)
    }

    func conversationHistory() -> [(role: String, content: String)] {
        return messages.map { ($0.role.rawValue, $0.content) }
    }

    func clear() {
        messages.removeAll()
    }
}

// MARK: - Binary Search Utility

extension Array {
    /// Binary search for the first index in a sorted array where `keyPath` is at or after `date`.
    /// The array must be sorted by the key in ascending order.
    func loopInsights_firstIndex(afterOrAt date: Date, by dateExtractor: (Element) -> Date) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if dateExtractor(self[mid]) < date {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}
