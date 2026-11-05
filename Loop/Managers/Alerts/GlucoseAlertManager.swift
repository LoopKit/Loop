//
//  GlucoseAlertManager.swift
//  Loop
//
//  Multi-profile glucose alert system modelled after Dexcom G7.
//  Users have a Primary profile (always present) plus any number of
//  additional profiles (e.g. "Night", "Exercise"). Each additional
//  profile can be manually activated or auto-scheduled by day-of-week
//  + time window. The active profile's thresholds govern all alerts.
//

import Combine
import Foundation
import LoopKit
#if canImport(LoopKitUI)
import LoopKitUI
#endif
import os.log

// MARK: - Sound catalog

/// The glucose alarms a sound can be chosen for. Themed sets are written per
/// alarm — the Urgent Low set is not the High set at another pitch — so each
/// set is only offered on the alarm it was written for.
enum GlucoseAlarmKind: String, CaseIterable {
    case urgentLow
    case low
    case predictedLow
    case high

    var displayName: String {
        switch self {
        case .urgentLow: return NSLocalizedString("Urgent Low", comment: "Name of the urgent low glucose alarm")
        case .low: return NSLocalizedString("Low", comment: "Name of the low glucose alarm")
        case .predictedLow: return NSLocalizedString("Predicted Low", comment: "Name of the predicted low glucose alarm")
        case .high: return NSLocalizedString("High", comment: "Name of the high glucose alarm")
        }
    }

    /// Identifier of the alert this alarm issues.
    var alertIdentifier: Alert.AlertIdentifier {
        switch self {
        case .urgentLow: return GlucoseAlertManager.urgentLowAlertIdentifier
        case .low: return GlucoseAlertManager.lowAlertIdentifier
        case .predictedLow: return GlucoseAlertManager.predictedLowAlertIdentifier
        case .high: return GlucoseAlertManager.highAlertIdentifier
        }
    }

    /// Identifier of this alarm's armed *test* alert. Deliberately distinct
    /// from the real one: a test then can't touch the real alarm's episode
    /// state, its retraction, or its AlarmKit alarm.
    var testAlertIdentifier: Alert.AlertIdentifier { "\(alertIdentifier).test" }

    /// Matches the real alarm's level. Getting past Focus and the silent
    /// switch is the whole point of the test, so the test has to ask for
    /// delivery on exactly the same terms.
    var interruptionLevel: Alert.InterruptionLevel {
        self == .urgentLow ? .critical : .timeSensitive
    }

    /// The alarm an alert identifier belongs to, real or test.
    static func kind(forAlertIdentifier identifier: Alert.AlertIdentifier) -> GlucoseAlarmKind? {
        allCases.first { $0.alertIdentifier == identifier || $0.testAlertIdentifier == identifier }
    }
}

/// How disruptive a themed alarm sounds. Intensity is carried by timbre,
/// loudness and length together — each level is its own recording, not one
/// recording at three gain settings.
enum AlarmUrgencyLevel: String, CaseIterable, Identifiable {
    case mild
    case medium
    case harsh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mild: return NSLocalizedString("Mild", comment: "Urgency level of a themed alarm sound")
        case .medium: return NSLocalizedString("Medium", comment: "Urgency level of a themed alarm sound")
        case .harsh: return NSLocalizedString("Harsh", comment: "Urgency level of a themed alarm sound")
        }
    }
}

/// Spoken alert voices.
enum AlarmVoice: String, CaseIterable, Identifiable {
    case amy
    case bryce

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amy: return NSLocalizedString("Amy", comment: "Name of a spoken alarm voice")
        case .bryce: return NSLocalizedString("Bryce", comment: "Name of a spoken alarm voice")
        }
    }
}

/// One selectable variant of a sound entry. `filename` is the bundled `.caf`
/// (also the `Alert.Sound` name stamped onto issued alerts) and is the only
/// thing persisted, so a stored selection survives any catalog reshuffle.
struct AlarmSound: Identifiable, Equatable {
    let id: String
    let displayName: String
    let filename: String
}

/// What the picker reveals once a themed entry is selected.
enum AlarmSoundSelector {
    case none
    case urgency
    case voice
}

/// One row in the sound picker. A themed entry carries several variants
/// behind one name (Acoustic at three urgency levels, Voice in two voices);
/// a generic tone carries exactly one.
struct AlarmSoundEntry: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// Empty means generic: offered on every alarm, under "Other Sounds".
    let kinds: [GlucoseAlarmKind]
    let selector: AlarmSoundSelector
    let variants: [AlarmSound]

    var isGeneric: Bool { kinds.isEmpty }
    var filenames: [String] { variants.map { $0.filename } }

    func variant(forFilename filename: String) -> AlarmSound? {
        variants.first { $0.filename == filename }
    }

    /// Middle of the urgency slider, and the set the sound designer
    /// recommends after hallway testing with PWDs and caregivers.
    var defaultVariant: AlarmSound {
        variants.first { $0.id == AlarmUrgencyLevel.medium.rawValue } ?? variants[0]
    }
}

/// The sounds available for glucose alarms. Each file is bundled in
/// Loop/Resources/Sounds and flattened to the app-bundle root (same as
/// `critical.caf`), so it's reachable both by `AVAudioPlayer` (in-process
/// critical fallback) and by the notification path once copied into
/// `Library/Sounds` via the AlertSoundVendor mechanism.
enum AlarmSoundCatalog {
    /// Filename slug per alarm, matching the sound designer's prefixes.
    private static let slugs: [(kind: GlucoseAlarmKind, slug: String)] = [
        (.urgentLow, "ulg"),
        (.low, "lg"),
        (.predictedLow, "lgs"),
        (.high, "hg"),
    ]

    private static func themed(_ theme: String, _ displayName: String) -> [AlarmSoundEntry] {
        slugs.map { kind, slug in
            AlarmSoundEntry(
                id: "\(theme).\(slug)",
                displayName: displayName,
                kinds: [kind],
                selector: .urgency,
                variants: AlarmUrgencyLevel.allCases.map {
                    AlarmSound(id: $0.rawValue, displayName: $0.displayName, filename: "\(theme)_\(slug)_\($0.rawValue).caf")
                }
            )
        }
    }

    private static let voiceEntries: [AlarmSoundEntry] = slugs.map { kind, slug in
        AlarmSoundEntry(
            id: "voice.\(slug)",
            displayName: NSLocalizedString("Voice", comment: "Name of the spoken alarm sound set"),
            kinds: [kind],
            selector: .voice,
            variants: AlarmVoice.allCases.map {
                AlarmSound(id: $0.rawValue, displayName: $0.displayName, filename: "voice_\(slug)_\($0.rawValue).caf")
            }
        )
    }

    private static let genericEntries: [AlarmSoundEntry] = [
        ("urgent_low.caf", NSLocalizedString("Urgent Low", comment: "Name of a glucose alarm sound")),
        ("critical.caf", NSLocalizedString("Sharp Alarm", comment: "Name of a glucose alarm sound")),
        ("alarm.caf", NSLocalizedString("Alarm", comment: "Name of a glucose alarm sound")),
        ("bright_alarm.caf", NSLocalizedString("Bright Alarm", comment: "Name of a glucose alarm sound")),
        ("honk.caf", NSLocalizedString("Honk", comment: "Name of a glucose alarm sound")),
        ("chime.caf", NSLocalizedString("Chime", comment: "Name of a glucose alarm sound")),
        ("clear_chimes.caf", NSLocalizedString("Clear Chimes", comment: "Name of a glucose alarm sound")),
        ("high_chimes.caf", NSLocalizedString("High Chimes", comment: "Name of a glucose alarm sound")),
        ("dings.caf", NSLocalizedString("Dings", comment: "Name of a glucose alarm sound")),
        ("trill.caf", NSLocalizedString("Trill", comment: "Name of a glucose alarm sound")),
        ("bloom.caf", NSLocalizedString("Bloom", comment: "Name of a glucose alarm sound")),
        ("bloop.caf", NSLocalizedString("Bloop", comment: "Name of a glucose alarm sound")),
        ("spring.caf", NSLocalizedString("Spring", comment: "Name of a glucose alarm sound")),
        ("minimal.caf", NSLocalizedString("Minimal", comment: "Name of a glucose alarm sound")),
        ("simple.caf", NSLocalizedString("Simple", comment: "Name of a glucose alarm sound")),
        ("synth.caf", NSLocalizedString("Synth", comment: "Name of a glucose alarm sound")),
        ("mood_synth.caf", NSLocalizedString("Mood Synth", comment: "Name of a glucose alarm sound")),
        ("crying.caf", NSLocalizedString("Crying", comment: "Name of a glucose alarm sound")),
        ("glass_bell.caf", NSLocalizedString("Glass Bell", comment: "Name of a glucose alarm sound")),
        ("harp.caf", NSLocalizedString("Harp", comment: "Name of a glucose alarm sound")),
        ("meow.caf", NSLocalizedString("Meow", comment: "Name of a glucose alarm sound")),
        ("saw_wave.caf", NSLocalizedString("Saw Wave", comment: "Name of a glucose alarm sound")),
        ("hard_saw_wave.caf", NSLocalizedString("Hard Saw Wave", comment: "Name of a glucose alarm sound")),
        ("sine_wave.caf", NSLocalizedString("Sine Wave", comment: "Name of a glucose alarm sound")),
        ("open_can.caf", NSLocalizedString("Open Can", comment: "Name of a glucose alarm sound")),
        ("open_wrapper.caf", NSLocalizedString("Open Wrapper", comment: "Name of a glucose alarm sound")),
    ].map { filename, name in
        AlarmSoundEntry(
            id: filename,
            displayName: name,
            kinds: [],
            selector: .none,
            variants: [AlarmSound(id: "default", displayName: name, filename: filename)]
        )
    }

    static let entries: [AlarmSoundEntry] = themed("acoustic", NSLocalizedString("Acoustic", comment: "Name of the acoustic themed alarm sound set"))
        + themed("electronic", NSLocalizedString("Electronic", comment: "Name of the electronic themed alarm sound set"))
        + voiceEntries
        + genericEntries

    static let allFilenames: [String] = entries.flatMap { $0.filenames }

    /// Themed sets written for this alarm, in display order.
    static func themedEntries(for kind: GlucoseAlarmKind) -> [AlarmSoundEntry] {
        entries.filter { $0.kinds.contains(kind) }
    }

    /// Generic tones, offered on every alarm.
    static var genericTones: [AlarmSoundEntry] { genericEntries }

    static func entry(forFilename filename: String) -> AlarmSoundEntry? {
        entries.first { $0.filenames.contains(filename) }
    }

    /// The themed default for an alarm: Acoustic, Medium.
    static func defaultFilename(for kind: GlucoseAlarmKind) -> String {
        themedEntries(for: kind).first { $0.id.hasPrefix("acoustic.") }?.defaultVariant.filename ?? "alarm.caf"
    }

    static func displayName(for filename: String) -> String {
        guard let entry = entry(forFilename: filename) else { return filename }
        guard !entry.isGeneric, let variant = entry.variant(forFilename: filename) else {
            return entry.displayName
        }
        return String(
            format: NSLocalizedString("%1$@ · %2$@", comment: "An alarm sound's set name and the chosen variant (1: set name, 2: variant name)"),
            entry.displayName, variant.displayName
        )
    }
}

// MARK: - Configuration

struct GlucoseAlertConfiguration: Equatable, Codable {
    var lowThresholdMgDL: Double
    var urgentLowThresholdMgDL: Double
    var highThresholdMgDL: Double

    /// BG must cross this many mg/dL past the threshold before re-arming.
    var recoveryMarginMgDL: Double

    var lowRepeatInterval: TimeInterval
    var urgentLowRepeatInterval: TimeInterval
    var highRepeatInterval: TimeInterval

    var lowEnabled: Bool
    var urgentLowEnabled: Bool
    var highEnabled: Bool

    var lowSnoozeEnabled: Bool
    var highSnoozeEnabled: Bool

    /// Delay the first high alert until BG has stayed above the threshold
    /// continuously for `highDelay`. Re-arms once BG recovers below threshold.
    var highDelayEnabled: Bool
    var highDelay: TimeInterval

    var predictedLowEnabled: Bool
    var predictedLowThresholdMgDL: Double
    var predictedLowHorizon: TimeInterval

    static let `default` = GlucoseAlertConfiguration(
        lowThresholdMgDL: 70,
        urgentLowThresholdMgDL: 55,
        highThresholdMgDL: 180,
        recoveryMarginMgDL: 5,
        lowRepeatInterval: 30 * 60,
        urgentLowRepeatInterval: 5 * 60,
        highRepeatInterval: 30 * 60,
        lowEnabled: true,
        urgentLowEnabled: true,
        highEnabled: true,
        lowSnoozeEnabled: false,
        highSnoozeEnabled: false,
        highDelayEnabled: false,
        highDelay: 30 * 60,
        predictedLowEnabled: true,
        predictedLowThresholdMgDL: 60,
        predictedLowHorizon: 20 * 60
    )
}

extension GlucoseAlertConfiguration {
    private enum CodingKeys: String, CodingKey {
        case lowThresholdMgDL, urgentLowThresholdMgDL, highThresholdMgDL
        case recoveryMarginMgDL
        case lowRepeatInterval, urgentLowRepeatInterval, highRepeatInterval
        case lowEnabled, urgentLowEnabled, highEnabled
        case lowSnoozeEnabled, highSnoozeEnabled
        case highDelayEnabled, highDelay
        case predictedLowEnabled, predictedLowThresholdMgDL, predictedLowHorizon
    }

    /// Custom decode so configs persisted before a field was introduced still
    /// load: a missing key falls back to the default rather than failing the
    /// whole decode, which would discard the user's saved profiles.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GlucoseAlertConfiguration.default
        lowThresholdMgDL = try c.decodeIfPresent(Double.self, forKey: .lowThresholdMgDL) ?? d.lowThresholdMgDL
        urgentLowThresholdMgDL = try c.decodeIfPresent(Double.self, forKey: .urgentLowThresholdMgDL) ?? d.urgentLowThresholdMgDL
        highThresholdMgDL = try c.decodeIfPresent(Double.self, forKey: .highThresholdMgDL) ?? d.highThresholdMgDL
        recoveryMarginMgDL = try c.decodeIfPresent(Double.self, forKey: .recoveryMarginMgDL) ?? d.recoveryMarginMgDL
        lowRepeatInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .lowRepeatInterval) ?? d.lowRepeatInterval
        urgentLowRepeatInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .urgentLowRepeatInterval) ?? d.urgentLowRepeatInterval
        highRepeatInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .highRepeatInterval) ?? d.highRepeatInterval
        lowEnabled = try c.decodeIfPresent(Bool.self, forKey: .lowEnabled) ?? d.lowEnabled
        urgentLowEnabled = try c.decodeIfPresent(Bool.self, forKey: .urgentLowEnabled) ?? d.urgentLowEnabled
        highEnabled = try c.decodeIfPresent(Bool.self, forKey: .highEnabled) ?? d.highEnabled
        lowSnoozeEnabled = try c.decodeIfPresent(Bool.self, forKey: .lowSnoozeEnabled) ?? d.lowSnoozeEnabled
        highSnoozeEnabled = try c.decodeIfPresent(Bool.self, forKey: .highSnoozeEnabled) ?? d.highSnoozeEnabled
        highDelayEnabled = try c.decodeIfPresent(Bool.self, forKey: .highDelayEnabled) ?? d.highDelayEnabled
        highDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .highDelay) ?? d.highDelay
        predictedLowEnabled = try c.decodeIfPresent(Bool.self, forKey: .predictedLowEnabled) ?? d.predictedLowEnabled
        predictedLowThresholdMgDL = try c.decodeIfPresent(Double.self, forKey: .predictedLowThresholdMgDL) ?? d.predictedLowThresholdMgDL
        predictedLowHorizon = try c.decodeIfPresent(TimeInterval.self, forKey: .predictedLowHorizon) ?? d.predictedLowHorizon
    }
}

// MARK: - Schedule settings

/// Auto-schedule for a non-primary profile.
/// When enabled, the profile activates at `startMinuteOfDay` on each
/// `activeDays` weekday and deactivates at `stopMinuteOfDay`.
/// An overnight window (stop < start) spans into the next calendar day.
struct GlucoseAlertScheduleSettings: Equatable, Codable {
    var enabled: Bool
    /// 0 = Sunday … 6 = Saturday.
    var activeDays: Set<Int>
    var startMinuteOfDay: Int
    var stopMinuteOfDay: Int

    static let `default` = GlucoseAlertScheduleSettings(
        enabled: false,
        activeDays: Set(0...6),
        startMinuteOfDay: 22 * 60,
        stopMinuteOfDay: 9 * 60
    )

    func isActive(at date: Date) -> Bool {
        guard enabled, !activeDays.isEmpty else { return false }
        let cal = Calendar.current
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: date)
        let weekday = (comps.weekday ?? 1) - 1
        let currentMinute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        if startMinuteOfDay < stopMinuteOfDay {
            guard activeDays.contains(weekday) else { return false }
            return currentMinute >= startMinuteOfDay && currentMinute < stopMinuteOfDay
        } else {
            if currentMinute >= startMinuteOfDay {
                return activeDays.contains(weekday)
            } else {
                let prevWeekday = (weekday + 6) % 7
                return activeDays.contains(prevWeekday) && currentMinute < stopMinuteOfDay
            }
        }
    }
}

// MARK: - Profile

struct GlucoseAlertProfile: Equatable, Codable, Identifiable {
    var id: UUID
    var name: String
    var configuration: GlucoseAlertConfiguration
    var scheduleSettings: GlucoseAlertScheduleSettings

    static func makePrimary() -> GlucoseAlertProfile {
        GlucoseAlertProfile(id: UUID(), name: "Primary", configuration: .default, scheduleSettings: .default)
    }

    static func makeSecondary(basedOn config: GlucoseAlertConfiguration = .default) -> GlucoseAlertProfile {
        GlucoseAlertProfile(
            id: UUID(),
            name: "Night",
            configuration: config,
            scheduleSettings: .default
        )
    }
}

// MARK: - Manager

@MainActor
final class GlucoseAlertManager: ObservableObject {
    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "GlucoseAlertManager")

    static let managerIdentifier = "GlucoseAlertManager"
    static let lowAlertIdentifier: Alert.AlertIdentifier = "glucose.low"
    static let urgentLowAlertIdentifier: Alert.AlertIdentifier = "glucose.urgentLow"
    static let highAlertIdentifier: Alert.AlertIdentifier = "glucose.high"
    static let predictedLowAlertIdentifier: Alert.AlertIdentifier = "glucose.predictedLow"

    private static let profilesKey = "GlucoseAlertProfiles"
    private static let activeProfileIDKey = "GlucoseAlertActiveProfileID"
    private static let urgentLowSoundKey = "GlucoseAlertUrgentLowSound"
    private static let lowSoundKey = "GlucoseAlertLowSound"
    private static let highSoundKey = "GlucoseAlertHighSound"
    private static let predictedLowSoundKey = "GlucoseAlertPredictedLowSound"
    private static let lowPlaysThroughSilentKey = "GlucoseAlertLowPlaysThroughSilent"
    private static let highPlaysThroughSilentKey = "GlucoseAlertHighPlaysThroughSilent"
    private static let predictedLowPlaysThroughSilentKey = "GlucoseAlertPredictedLowPlaysThroughSilent"
    static let episodeStateKey = "GlucoseAlertEpisodeState"
    private static let armedTestKey = "GlucoseAlertArmedTest"

    // Per-alarm sound defaults: each alarm's own Acoustic set at Medium, the
    // variant the sound designer recommends after testing with PWDs.
    static let defaultUrgentLowSound = AlarmSoundCatalog.defaultFilename(for: .urgentLow)
    static let defaultLowSound = AlarmSoundCatalog.defaultFilename(for: .low)
    static let defaultHighSound = AlarmSoundCatalog.defaultFilename(for: .high)
    static let defaultPredictedLowSound = AlarmSoundCatalog.defaultFilename(for: .predictedLow)
    static let defaultLowPlaysThroughSilent = true
    static let defaultHighPlaysThroughSilent = false
    static let defaultPredictedLowPlaysThroughSilent = true
    private static let overrideKey = "GlucoseAlertLoopOverride"
    private static let legacyConfigKey = "GlucoseAlertConfiguration"
    private static let legacyPrimaryKey = "GlucoseAlertPrimaryConfig"
    private static let legacyAlternateKey = "GlucoseAlertAlternateProfile"
    // Keys written by intermediate WIP builds — never part of a release, must be
    // cleaned up on first launch so stale data can't interfere with CGM restoration.
    private static let wipeOnMigrationKeys: [String] = [
        "GlucoseAlertSchedules",
        "GlucoseAlertActiveScheduleIndex",
    ]

    private let alertIssuer: AlertIssuer
    private let displayGlucosePreference: DisplayGlucosePreference
    private let userDefaults: UserDefaults

    /// Ordered list of profiles; `profiles[0]` is always Primary.
    @Published var profiles: [GlucoseAlertProfile] {
        didSet { guard profiles != oldValue else { return }; persistProfiles() }
    }

    /// ID of the currently-active profile.
    @Published var activeProfileID: UUID {
        didSet {
            guard activeProfileID != oldValue else { return }
            userDefaults.set(activeProfileID.uuidString, forKey: Self.activeProfileIDKey)
        }
    }

    @Published var loopAlertsOverrideForOwnAlertingCGM: Bool {
        didSet { userDefaults.set(loopAlertsOverrideForOwnAlertingCGM, forKey: Self.overrideKey) }
    }

    /// Global per-alarm sound selection (filename in AlarmSoundCatalog). These
    /// are global rather than per-profile: the sound identifies the alarm
    /// type, not the threshold profile. Stamped onto each issued Alert so both
    /// the notification path and the in-process critical player use it.
    @Published var urgentLowSound: String {
        didSet { userDefaults.set(urgentLowSound, forKey: Self.urgentLowSoundKey) }
    }
    @Published var lowSound: String {
        didSet { userDefaults.set(lowSound, forKey: Self.lowSoundKey) }
    }
    @Published var highSound: String {
        didSet { userDefaults.set(highSound, forKey: Self.highSoundKey) }
    }
    @Published var predictedLowSound: String {
        didSet { userDefaults.set(predictedLowSound, forKey: Self.predictedLowSoundKey) }
    }

    /// Whether a non-urgent alarm plays its sound in-app, through the silent switch and Focus.
    /// Urgent low always does, as a critical alert.
    @Published var lowPlaysThroughSilent: Bool {
        didSet { userDefaults.set(lowPlaysThroughSilent, forKey: Self.lowPlaysThroughSilentKey) }
    }
    @Published var highPlaysThroughSilent: Bool {
        didSet { userDefaults.set(highPlaysThroughSilent, forKey: Self.highPlaysThroughSilentKey) }
    }
    @Published var predictedLowPlaysThroughSilent: Bool {
        didSet { userDefaults.set(predictedLowPlaysThroughSilent, forKey: Self.predictedLowPlaysThroughSilentKey) }
    }

    func playsThroughSilent(for identifier: Alert.AlertIdentifier) -> Bool {
        switch GlucoseAlarmKind.kind(forAlertIdentifier: identifier) {
        case .low:            return lowPlaysThroughSilent
        case .high:           return highPlaysThroughSilent
        case .predictedLow:   return predictedLowPlaysThroughSilent
        case .urgentLow, nil: return false
        }
    }

    /// The configured sound filename for a given glucose alarm identifier.
    func configuredSoundName(for identifier: Alert.AlertIdentifier) -> String {
        switch GlucoseAlarmKind.kind(forAlertIdentifier: identifier) {
        case .urgentLow:    return urgentLowSound
        case .low:          return lowSound
        case .high:         return highSound
        case .predictedLow: return predictedLowSound
        case nil:           return Self.defaultUrgentLowSound
        }
    }

    @Published var cgmProvidesOwnAlerts: Bool = false

    var effectiveLoopAlertsEnabled: Bool {
        !cgmProvidesOwnAlerts || loopAlertsOverrideForOwnAlertingCGM
    }

    /// True while another controller raises these alerts for this user; nothing is evaluated here.
    var alertsHandledElsewhere: () -> Bool = { false }

    // MARK: - Profile access

    var primaryProfile: GlucoseAlertProfile { profiles[0] }

    func profile(id: UUID) -> GlucoseAlertProfile? {
        profiles.first { $0.id == id }
    }

    func activeProfile(at date: Date = Date()) -> GlucoseAlertProfile {
        profile(id: activeProfileID) ?? primaryProfile
    }

    func activeConfiguration(at date: Date = Date()) -> GlucoseAlertConfiguration {
        activeProfile(at: date).configuration
    }

    // MARK: - Profile management

    func activate(profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        activeProfileID = profileID
    }

    func addProfile() -> UUID {
        let base = activeProfile().configuration
        let new = GlucoseAlertProfile.makeSecondary(basedOn: base)
        profiles.append(new)
        return new.id
    }

    func removeProfile(id: UUID) {
        guard profiles.count > 1, profiles[0].id != id else { return }
        if activeProfileID == id { activeProfileID = profiles[0].id }
        profiles.removeAll { $0.id == id }
    }

    /// Restore all glucose-alert settings to their factory defaults: a single
    /// Primary profile with default thresholds/schedule, default per-alarm
    /// sounds, and the Loop-override toggle off.
    func resetToDefaults() {
        let primary = GlucoseAlertProfile.makePrimary()
        profiles = [primary]
        activeProfileID = primary.id
        urgentLowSound = Self.defaultUrgentLowSound
        lowSound = Self.defaultLowSound
        highSound = Self.defaultHighSound
        predictedLowSound = Self.defaultPredictedLowSound
        lowPlaysThroughSilent = Self.defaultLowPlaysThroughSilent
        highPlaysThroughSilent = Self.defaultHighPlaysThroughSilent
        predictedLowPlaysThroughSilent = Self.defaultPredictedLowPlaysThroughSilent
        loopAlertsOverrideForOwnAlertingCGM = false
    }

    // MARK: - Scheduling

    /// Per-profile tracking of whether we were in the scheduled window on the last check.
    private var wasInScheduledWindow: [UUID: Bool] = [:]

    private func checkSchedule(at now: Date) {
        for profile in profiles.dropFirst() {
            guard profile.scheduleSettings.enabled else { continue }
            let inWindow = profile.scheduleSettings.isActive(at: now)
            let wasIn = wasInScheduledWindow[profile.id] ?? false

            if inWindow && !wasIn && activeProfileID == primaryProfile.id {
                os_log("Schedule: activating profile '%{public}@'", log: log, type: .info, profile.name)
                activeProfileID = profile.id
            } else if !inWindow && wasIn && activeProfileID == profile.id {
                os_log("Schedule: deactivating profile '%{public}@'", log: log, type: .info, profile.name)
                activeProfileID = primaryProfile.id
            }
            wasInScheduledWindow[profile.id] = inWindow
        }
    }

    // MARK: - Next transition label

    func nextTransitionLabel(for profileID: UUID, at now: Date = Date()) -> String? {
        guard let profile = profile(id: profileID), profile.scheduleSettings.enabled else { return nil }
        guard let transition = nextScheduledTransition(settings: profile.scheduleSettings, at: now) else { return nil }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEEjmm")
        let dateStr = fmt.string(from: transition.at)
        return transition.activating
            ? "Scheduled to turn on: \(dateStr)"
            : "Scheduled to turn off: \(dateStr)"
    }

    private func nextScheduledTransition(
        settings: GlucoseAlertScheduleSettings,
        at now: Date
    ) -> (activating: Bool, at: Date)? {
        let cal = Calendar.current
        let currentlyInWindow = settings.isActive(at: now)

        for dayOffset in 0...8 {
            guard let candidateDay = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = cal.component(.weekday, from: candidateDay) - 1

            if settings.activeDays.contains(weekday),
               let startDate = minuteDate(settings.startMinuteOfDay, on: candidateDay, cal: cal),
               startDate > now, !currentlyInWindow {
                return (activating: true, at: startDate)
            }

            let isStopDay: Bool
            if settings.startMinuteOfDay < settings.stopMinuteOfDay {
                isStopDay = settings.activeDays.contains(weekday)
            } else {
                isStopDay = settings.activeDays.contains((weekday + 6) % 7)
            }
            if isStopDay,
               let stopDate = minuteDate(settings.stopMinuteOfDay, on: candidateDay, cal: cal),
               stopDate > now, currentlyInWindow {
                return (activating: false, at: stopDate)
            }
        }
        return nil
    }

    private func minuteDate(_ minuteOfDay: Int, on day: Date, cal: Calendar) -> Date? {
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = minuteOfDay / 60
        comps.minute = minuteOfDay % 60
        comps.second = 0
        return cal.date(from: comps)
    }

    func formatMinuteOfDay(_ minuteOfDay: Int) -> String {
        var comps = DateComponents()
        comps.hour = minuteOfDay / 60
        comps.minute = minuteOfDay % 60
        guard let date = Calendar.current.date(from: comps) else { return "" }
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    // MARK: - Hysteresis

    private struct AlertState: Equatable, Codable {
        var inBoundary: Bool = false
        var lastFiredAt: Date?
        /// When BG first crossed into the alert boundary this episode. Used to
        /// honor a configured first-alert delay. Reset on recovery.
        var boundaryEnteredAt: Date?
    }

    /// Episode state survives relaunch: without it a restart clears
    /// `lastFiredAt` and the next in-boundary reading re-alerts something the
    /// user already acknowledged, and defeats an active snooze.
    private struct EpisodeState: Codable {
        var low: AlertState
        var urgentLow: AlertState
        var high: AlertState
        var predictedLowInEpisode: Bool
    }
    private var lowState = AlertState() { didSet { persistEpisodeState() } }
    private var urgentLowState = AlertState() { didSet { persistEpisodeState() } }
    private var highState = AlertState() { didSet { persistEpisodeState() } }
    private var predictedLowInEpisode = false { didSet { persistEpisodeState() } }
    /// Most recent real CGM reading. Used to suppress a redundant predicted-low
    /// alert when glucose is already at/below the Low threshold.
    private var latestReading: (mgdl: Double, date: Date)?
    private var cancellables = Set<AnyCancellable>()

    /// The alarm whose test is armed, if any. One at a time; arming another
    /// replaces it. The test waits for the next CGM reading (or the next loop
    /// cycle, for Predicted Low) so it is delivered from whatever state Loop
    /// is actually in — backgrounded, screen locked, phone in a Focus — which
    /// is the thing the user is trying to check.
    ///
    /// Persisted, because iOS may terminate a backgrounded Loop before the
    /// next reading arrives, and a test that quietly evaporates reads exactly
    /// like an alarm that doesn't work.
    @Published private(set) var armedTest: GlucoseAlarmKind? {
        didSet {
            if let armedTest {
                userDefaults.set(armedTest.rawValue, forKey: Self.armedTestKey)
            } else {
                userDefaults.removeObject(forKey: Self.armedTestKey)
            }
        }
    }

    // MARK: - Init

    init(alertIssuer: AlertIssuer,
         displayGlucosePreference: DisplayGlucosePreference,
         userDefaults: UserDefaults = .standard) {
        self.alertIssuer = alertIssuer
        self.displayGlucosePreference = displayGlucosePreference
        self.userDefaults = userDefaults

        var loadedProfiles: [GlucoseAlertProfile]
        var migratedOverride = false
        var didMigrate = false

        if let data = userDefaults.data(forKey: Self.profilesKey),
           let saved = try? JSONDecoder().decode([GlucoseAlertProfile].self, from: data), !saved.isEmpty {
            loadedProfiles = saved
        } else {
            didMigrate = true
            // Migration from the v1 flat format (single GlucoseAlertConfiguration with
            // loopAlertsOverrideForOwnAlertingCGM embedded) or the two-profile WIP format.
            var primary = GlucoseAlertProfile.makePrimary()
            if let data = userDefaults.data(forKey: Self.legacyPrimaryKey),
               let cfg = try? JSONDecoder().decode(GlucoseAlertConfiguration.self, from: data) {
                primary.configuration = cfg
            } else if let data = userDefaults.data(forKey: Self.legacyConfigKey),
                      let cfg = try? JSONDecoder().decode(GlucoseAlertConfiguration.self, from: data) {
                primary.configuration = cfg
                // v1 stored loopAlertsOverrideForOwnAlertingCGM inside the config blob.
                if let override = (try? JSONDecoder().decode(LegacyV1Config.self, from: data))?.loopAlertsOverrideForOwnAlertingCGM {
                    migratedOverride = override
                }
            }
            loadedProfiles = [primary]

            if let data = userDefaults.data(forKey: Self.legacyAlternateKey),
               let alt = try? JSONDecoder().decode(LegacyAlternateProfile.self, from: data) {
                var secondary = GlucoseAlertProfile.makeSecondary(basedOn: alt.configuration)
                secondary.name = alt.name
                secondary.scheduleSettings = alt.scheduleSettings
                loadedProfiles.append(secondary)
            }
        }

        self.profiles = loadedProfiles

        let savedIDStr = userDefaults.string(forKey: Self.activeProfileIDKey)
        let savedID = savedIDStr.flatMap(UUID.init)
        if let id = savedID, loadedProfiles.contains(where: { $0.id == id }) {
            self.activeProfileID = id
        } else {
            self.activeProfileID = loadedProfiles[0].id
        }

        self.loopAlertsOverrideForOwnAlertingCGM = didMigrate && migratedOverride
            ? migratedOverride
            : userDefaults.bool(forKey: Self.overrideKey)

        self.urgentLowSound = userDefaults.string(forKey: Self.urgentLowSoundKey) ?? Self.defaultUrgentLowSound
        self.lowSound = userDefaults.string(forKey: Self.lowSoundKey) ?? Self.defaultLowSound
        self.highSound = userDefaults.string(forKey: Self.highSoundKey) ?? Self.defaultHighSound
        self.predictedLowSound = userDefaults.string(forKey: Self.predictedLowSoundKey) ?? Self.defaultPredictedLowSound
        self.lowPlaysThroughSilent = userDefaults.object(forKey: Self.lowPlaysThroughSilentKey) as? Bool ?? Self.defaultLowPlaysThroughSilent
        self.highPlaysThroughSilent = userDefaults.object(forKey: Self.highPlaysThroughSilentKey) as? Bool ?? Self.defaultHighPlaysThroughSilent
        self.predictedLowPlaysThroughSilent = userDefaults.object(forKey: Self.predictedLowPlaysThroughSilentKey) as? Bool ?? Self.defaultPredictedLowPlaysThroughSilent

        if didMigrate {
            // Write new format and erase all legacy + WIP keys atomically so
            // stale data from intermediate builds can never cause decode failures
            // or interfere with CGM restoration on subsequent launches.
            if let data = try? JSONEncoder().encode(loadedProfiles) {
                userDefaults.set(data, forKey: Self.profilesKey)
            }
            let keysToRemove = [Self.legacyConfigKey, Self.legacyPrimaryKey, Self.legacyAlternateKey]
                + Self.wipeOnMigrationKeys
            for key in keysToRemove { userDefaults.removeObject(forKey: key) }
        }

        self.armedTest = userDefaults.string(forKey: Self.armedTestKey).flatMap(GlucoseAlarmKind.init(rawValue:))

        if let data = userDefaults.data(forKey: Self.episodeStateKey),
           let saved = try? JSONDecoder().decode(EpisodeState.self, from: data) {
            lowState = saved.low
            urgentLowState = saved.urgentLow
            highState = saved.high
            predictedLowInEpisode = saved.predictedLowInEpisode
        }

        NotificationCenter.default.publisher(for: .LoopCycleCompleted)
            .sink { [weak self] notification in
                guard let predicted = (notification.object as? LoopDataManager)?.predictedGlucose else { return }
                Task { @MainActor in await self?.evaluatePredictedGlucose(predicted) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Test support

    /// Arm a test of one alarm, to be delivered alongside the next reading.
    func armTest(for kind: GlucoseAlarmKind) {
        armedTest = kind
        os_log("Test armed for %{public}@", log: log, type: .info, kind.rawValue)
    }

    func cancelArmedTest() { armedTest = nil }

    /// Issue the armed test alert for `kind`, if that's the one armed.
    ///
    /// The test alert carries the alarm's configured sound and its real
    /// interruption level — critical for Urgent Low, time-sensitive for the
    /// rest — so it exercises the same delivery path, including the AlarmKit
    /// and in-app audio fallbacks. It carries its own identifier and is issued
    /// in addition to (never in place of) the normal evaluation, so no reading
    /// is substituted or discarded and no real alarm's state is touched.
    private func fireArmedTest(for kind: GlucoseAlarmKind) async {
        guard armedTest == kind else { return }
        armedTest = nil
        let content = Alert.Content(
            title: String(
                format: NSLocalizedString("%1$@ Alert Test", comment: "Title of a test glucose alert (1: alarm name)"),
                kind.displayName
            ),
            body: NSLocalizedString(
                "This is a test of this alarm's sound and delivery. Your glucose has not crossed the level.",
                comment: "Body of a test glucose alert"
            ),
            acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Acknowledge button on a test glucose alert")
        )
        let alert = Alert(
            identifier: Alert.Identifier(managerIdentifier: Self.managerIdentifier, alertIdentifier: kind.testAlertIdentifier),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: kind.interruptionLevel,
            sound: .sound(name: configuredSoundName(for: kind.testAlertIdentifier))
        )
        os_log("Firing armed test for %{public}@", log: log, type: .info, kind.rawValue)
        await alertIssuer.issueAlert(alert)
    }

    // MARK: - Persistence

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        userDefaults.set(data, forKey: Self.profilesKey)
    }

    private func persistEpisodeState() {
        let state = EpisodeState(low: lowState, urgentLow: urgentLowState,
                                 high: highState, predictedLowInEpisode: predictedLowInEpisode)
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: Self.episodeStateKey)
    }

    private func forgetEpisodes() {
        lowState = AlertState()
        urgentLowState = AlertState()
        highState = AlertState()
        predictedLowInEpisode = false
    }

    // MARK: - Alert text

    /// Renders a canonical mg/dL value in the unit the user reads glucose in.
    /// Thresholds and readings are *stored* in mg/dL throughout; only the text
    /// the user sees converts, and it goes through the same preference the
    /// settings screen formats with so the two always agree.
    private func formatGlucose(_ mgdl: Double, includeUnit: Bool = true) -> String {
        displayGlucosePreference.format(
            LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: mgdl),
            includeUnit: includeUnit
        )
    }

    // MARK: - Evaluation

    func evaluate(samples: [NewGlucoseSample], now: Date = Date()) async {
        guard effectiveLoopAlertsEnabled else { return }
        // Readings evaluated elsewhere close no episode here, so the next spell starts from none.
        guard !alertsHandledElsewhere() else { forgetEpisodes(); return }
        checkSchedule(at: now)
        guard let latest = samples.max(by: { $0.date < $1.date }) else { return }
        guard now.timeIntervalSince(latest.date) < 6 * 60 else {
            os_log("Skipping stale sample", log: log, type: .debug)
            return
        }
        // CGMs deliver the live reading and then backfill. A batch whose newest
        // sample is no newer than the one already evaluated must not re-decide
        // — and in particular must not retract — the alert that reading raised.
        if let evaluated = latestReading, latest.date <= evaluated.date {
            os_log("Skipping batch older than the latest evaluated reading", log: log, type: .debug)
            return
        }
        latestReading = (latest.quantity.doubleValue(for: .milligramsPerDeciliter), latest.date)
        let config = activeConfiguration(at: now)
        let mgdl = latest.quantity.doubleValue(for: .milligramsPerDeciliter)
        // Low and urgent-low are mutually exclusive: a reading below the
        // urgent-low threshold is also below the low threshold, so issuing both
        // in the same check is redundant. As a rule, only surface the most
        // severe applicable alert — when urgent low applies it supersedes low.
        let urgentLowSupersedes = config.urgentLowEnabled && mgdl < config.urgentLowThresholdMgDL
        await evaluateLow(mgdl: mgdl, config: config, now: now, supersededByUrgentLow: urgentLowSupersedes)
        await evaluateUrgentLow(mgdl: mgdl, config: config, now: now)
        await evaluateHigh(mgdl: mgdl, config: config, now: now)

        // An armed test rides along with a real reading so it arrives from
        // whatever state Loop is in at that moment, but it is issued on its own
        // identifier and leaves the evaluation above untouched.
        if let armed = armedTest, armed != .predictedLow {
            await fireArmedTest(for: armed)
        }
    }

    private func evaluateLow(mgdl: Double, config: GlucoseAlertConfiguration, now: Date, supersededByUrgentLow: Bool) async {
        guard config.lowEnabled else { return }
        let threshold = config.lowThresholdMgDL
        if mgdl < threshold {
            guard !supersededByUrgentLow else {
                // The more severe urgent-low alert covers this reading. Don't
                // also issue a low alert; retract any low alert still showing
                // from before BG fell into the urgent range so the two never
                // coexist. Resetting the boundary state lets a fresh low alert
                // fire if BG later recovers into the low (non-urgent) band while
                // still below the low threshold.
                if let id = takeRetractID(state: &lowState, identifier: Self.lowAlertIdentifier) {
                    await alertIssuer.retractAlert(identifier: id)
                }
                return
            }
            let alert = decideAndUpdate(
                state: &lowState, identifier: Self.lowAlertIdentifier, interruptionLevel: .timeSensitive,
                title: NSLocalizedString("Low Glucose", comment: "Title of the low glucose alert"),
                body: String(
                    format: NSLocalizedString("Glucose is below %1$@ (current: %2$@)",
                                              comment: "Body of the low glucose alert (1: threshold with unit, 2: current glucose)"),
                    formatGlucose(threshold), formatGlucose(mgdl, includeUnit: false)
                ),
                delay: nil,
                repeatInterval: config.lowSnoozeEnabled ? config.lowRepeatInterval : nil, now: now
            )
            if let alert { await alertIssuer.issueAlert(alert) }
        } else if mgdl > threshold + config.recoveryMarginMgDL {
            if let id = takeRetractID(state: &lowState, identifier: Self.lowAlertIdentifier) {
                await alertIssuer.retractAlert(identifier: id)
            }
        }
    }

    private func evaluateUrgentLow(mgdl: Double, config: GlucoseAlertConfiguration, now: Date) async {
        guard config.urgentLowEnabled else { return }
        let threshold = config.urgentLowThresholdMgDL
        if mgdl < threshold {
            let alert = decideAndUpdate(
                state: &urgentLowState, identifier: Self.urgentLowAlertIdentifier, interruptionLevel: .critical,
                title: NSLocalizedString("Urgent Low Glucose", comment: "Title of the urgent low glucose alert"),
                body: String(
                    format: NSLocalizedString("Glucose is below %1$@ (current: %2$@). Treat now.",
                                              comment: "Body of the urgent low glucose alert (1: threshold with unit, 2: current glucose)"),
                    formatGlucose(threshold), formatGlucose(mgdl, includeUnit: false)
                ),
                delay: nil,
                repeatInterval: config.urgentLowRepeatInterval, now: now
            )
            if let alert { await alertIssuer.issueAlert(alert) }
        } else if mgdl > threshold + config.recoveryMarginMgDL {
            if let id = takeRetractID(state: &urgentLowState, identifier: Self.urgentLowAlertIdentifier) {
                await alertIssuer.retractAlert(identifier: id)
            }
        }
    }

    private func evaluateHigh(mgdl: Double, config: GlucoseAlertConfiguration, now: Date) async {
        guard config.highEnabled else { return }
        let threshold = config.highThresholdMgDL
        if mgdl > threshold {
            let alert = decideAndUpdate(
                state: &highState, identifier: Self.highAlertIdentifier, interruptionLevel: .timeSensitive,
                title: NSLocalizedString("High Glucose", comment: "Title of the high glucose alert"),
                body: String(
                    format: NSLocalizedString("Glucose is above %1$@ (current: %2$@)",
                                              comment: "Body of the high glucose alert (1: threshold with unit, 2: current glucose)"),
                    formatGlucose(threshold), formatGlucose(mgdl, includeUnit: false)
                ),
                delay: config.highDelayEnabled ? config.highDelay : nil,
                repeatInterval: config.highSnoozeEnabled ? config.highRepeatInterval : nil, now: now
            )
            if let alert { await alertIssuer.issueAlert(alert) }
        } else if mgdl < threshold - config.recoveryMarginMgDL {
            if let id = takeRetractID(state: &highState, identifier: Self.highAlertIdentifier) {
                await alertIssuer.retractAlert(identifier: id)
            }
        }
    }

    private func takeRetractID(state: inout AlertState, identifier: Alert.AlertIdentifier) -> Alert.Identifier? {
        let wasActive = state.inBoundary
        state = AlertState()
        guard wasActive else { return nil }
        return Alert.Identifier(managerIdentifier: Self.managerIdentifier, alertIdentifier: identifier)
    }

    func evaluatePredictedGlucose(_ predicted: [PredictedGlucoseValue], now: Date = Date()) async {
        guard effectiveLoopAlertsEnabled, !alertsHandledElsewhere() else { return }
        let config = activeConfiguration(at: now)
        guard config.predictedLowEnabled else { return }

        // Predicted Low has no reading of its own to ride along with; its test
        // goes out on the next completed loop cycle instead.
        if armedTest == .predictedLow {
            await fireArmedTest(for: .predictedLow)
        }

        func retractIfActive() async {
            guard predictedLowInEpisode else { return }
            predictedLowInEpisode = false
            await alertIssuer.retractAlert(
                identifier: Alert.Identifier(managerIdentifier: Self.managerIdentifier, alertIdentifier: Self.predictedLowAlertIdentifier)
            )
        }

        // A predicted-low warns you're *trending* toward a low. If you're
        // already at/below your Low threshold, the Low alert already covers it
        // and a separate "predicted low" is redundant and confusing — suppress
        // it (requires a fresh reading to confirm you're currently low).
        if let reading = latestReading,
           now.timeIntervalSince(reading.date) < 15 * 60,
           reading.mgdl < config.lowThresholdMgDL {
            await retractIfActive()
            return
        }

        let horizonEnd = now.addingTimeInterval(config.predictedLowHorizon)
        let threshold = config.predictedLowThresholdMgDL
        let crossesLow = predicted.contains {
            $0.startDate > now && $0.startDate <= horizonEnd
                && $0.quantity.doubleValue(for: .milligramsPerDeciliter) < threshold
        }
        if !crossesLow {
            await retractIfActive()
            return
        }
        guard !predictedLowInEpisode else { return }
        predictedLowInEpisode = true
        let content = Alert.Content(
            title: NSLocalizedString("Predicted Low Glucose", comment: "Title of the predicted low glucose alert"),
            body: String(
                format: NSLocalizedString("Loop predicts glucose below %1$@ within %2$d min.",
                                          comment: "Body of the predicted low glucose alert (1: threshold with unit, 2: minutes of the prediction horizon)"),
                formatGlucose(threshold), Int(config.predictedLowHorizon / 60)
            ),
            acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Acknowledge button on a glucose alert"))
        let alert = Alert(
            identifier: Alert.Identifier(managerIdentifier: Self.managerIdentifier, alertIdentifier: Self.predictedLowAlertIdentifier),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate, interruptionLevel: .timeSensitive,
            sound: .sound(name: configuredSoundName(for: Self.predictedLowAlertIdentifier))
        )
        await alertIssuer.issueAlert(alert)
    }

    private func decideAndUpdate(
        state: inout AlertState, identifier: Alert.AlertIdentifier,
        interruptionLevel: Alert.InterruptionLevel,
        title: String, body: String, delay: TimeInterval?, repeatInterval: TimeInterval?, now: Date
    ) -> Alert? {
        if !state.inBoundary {
            state.inBoundary = true
            state.boundaryEnteredAt = now
        }
        let shouldFire: Bool
        if state.lastFiredAt == nil {
            // First alert of this episode: hold off until BG has stayed in the
            // boundary for the configured delay.
            if let delay, let entered = state.boundaryEnteredAt, now.timeIntervalSince(entered) < delay {
                shouldFire = false
            } else {
                shouldFire = true
            }
        } else if let repeatInterval, let last = state.lastFiredAt, now.timeIntervalSince(last) >= repeatInterval {
            shouldFire = true
        } else {
            shouldFire = false
        }
        guard shouldFire else { return nil }
        state.lastFiredAt = now
        let content = Alert.Content(
            title: title, body: body,
            acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Acknowledge button on a glucose alert"))
        return Alert(
            identifier: Alert.Identifier(managerIdentifier: Self.managerIdentifier, alertIdentifier: identifier),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate, interruptionLevel: interruptionLevel,
            sound: .sound(name: configuredSoundName(for: identifier))
        )
    }
}

// MARK: - AlertSoundVendor

extension GlucoseAlertManager: AlertSoundVendor {
    // The .caf files are bundled as individual resources, so they're
    // flattened to the app-bundle root (same as critical.caf). The
    // AlertManager copies each into Library/Sounds/GlucoseAlertManager-<file>
    // so the notification path can resolve them by name.
    nonisolated func getSoundBaseURL() -> URL? {
        Bundle.main.resourceURL
    }

    nonisolated func getSounds() -> [Alert.Sound] {
        AlarmSoundCatalog.allFilenames.map { .sound(name: $0) }
    }
}

// MARK: - Legacy migration shims

/// v1 stored loopAlertsOverrideForOwnAlertingCGM inside GlucoseAlertConfiguration.
/// Decode only the one field we need to migrate.
private struct LegacyV1Config: Codable {
    var loopAlertsOverrideForOwnAlertingCGM: Bool?
}

private struct LegacyAlternateProfile: Codable {
    var name: String
    var configuration: GlucoseAlertConfiguration
    var scheduleSettings: GlucoseAlertScheduleSettings
}
