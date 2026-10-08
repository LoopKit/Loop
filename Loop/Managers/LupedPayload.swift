#if LUPED_PEBBLE
import Foundation
import LoopAlgorithm
import LoopKit

/// Glucose alarm settings mirrored to the Luped watchface from Loop's active
/// glucose alert profile.
struct LupedAlarmSettings: Equatable {
    /// Luped's alarm-enable bitmask (`DATA` index 9). Older Luped builds read
    /// any non-zero value as "all alarms on".
    static let urgentLowBit = 1
    static let lowBit = 2
    static let highBit = 4

    /// A repeat interval long enough that the watch alarms once per episode;
    /// Luped re-arms when glucose returns to range.
    static let oncePerEpisode = TimeInterval(hours: 24)

    var urgentLowMgDL: Double
    var lowMgDL: Double
    var highMgDL: Double
    var enabledMask: Int
    var urgentLowRepeat: TimeInterval
    var lowRepeat: TimeInterval
    var highRepeat: TimeInterval

    /// Display-only defaults with alarms off, used without alert settings.
    static let disabled = LupedAlarmSettings(
        urgentLowMgDL: 55,
        lowMgDL: 80,
        highMgDL: 200,
        enabledMask: 0,
        urgentLowRepeat: oncePerEpisode,
        lowRepeat: oncePerEpisode,
        highRepeat: oncePerEpisode
    )
}

/// The AppMessage `DATA` value understood by the Luped watchface.
///
/// Values are deliberately constructed from stored glucose samples rather than
/// CGM-manager-specific display state, so every supported CGM follows the same
/// path and a restarted app can restore the watchface from persisted history.
struct LupedPayload: Equatable {
    /// History needed to fill the watchface graph at a 5-minute CGM cadence.
    static let historyInterval = TimeInterval(hours: 2)

    /// Readings further apart than this are not used for delta or computed trend.
    private static let maximumDeltaInterval = TimeInterval(minutes: 15)

    let data: String
    /// Start date of the latest reading, for diagnostics.
    let latestDate: Date
    /// Number of readings in the history graph, for diagnostics.
    let readingCount: Int
    /// Each `DATA` field with its meaning, one per line, for the communication log.
    let fieldDescription: String

    private static let directionNames = ["DoubleDown", "SingleDown", "FortyFiveDown", "Flat", "FortyFiveUp", "SingleUp", "DoubleUp"]

    init?(samples: [StoredGlucoseSample], unit: LoopUnit, alarms: LupedAlarmSettings) {
        let readings = samples
            .filter { !$0.wasUserEntered && !$0.isDisplayOnly }
            .sorted { $0.startDate < $1.startDate }
            .suffix(12)
        guard let latest = readings.last else {
            return nil
        }

        let values = readings.map { sample in
            Self.rounded(sample.quantity.doubleValue(for: unit), for: unit)
        }
        let previous = Self.previousReading(in: readings)
        let delta = previous.map { latest.quantity.doubleValue(for: unit) - $0.quantity.doubleValue(for: unit) } ?? 0
        let direction = latest.trend.map(Self.directionIndex(for:)) ?? Self.directionIndex(from: previous, to: latest)
        func converted(_ milligramsPerDeciliter: Double) -> NSDecimalNumber {
            Self.rounded(LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: milligramsPerDeciliter).doubleValue(for: unit), for: unit)
        }
        func minutes(_ interval: TimeInterval) -> Int {
            max(1, Int((interval / 60).rounded()))
        }
        let timestamp = Int64(latest.startDate.timeIntervalSince1970 * 1_000)

        let message: [Any] = [
            1,
            values[values.count - 1],
            Self.rounded(delta, for: unit),
            direction,
            values,
            unit == .millimolesPerLiter ? 1 : 0,
            converted(alarms.urgentLowMgDL),
            converted(alarms.lowMgDL),
            converted(alarms.highMgDL),
            alarms.enabledMask,
            minutes(alarms.lowRepeat),
            minutes(alarms.highRepeat),
            timestamp,
            0,
            minutes(alarms.urgentLowRepeat)
        ]

        guard JSONSerialization.isValidJSONObject(message),
              let encoded = try? JSONSerialization.data(withJSONObject: message),
              let data = String(data: encoded, encoding: .utf8)
        else {
            return nil
        }

        self.data = data
        self.latestDate = latest.startDate
        self.readingCount = readings.count

        func repeatText(_ interval: TimeInterval) -> String {
            interval >= LupedAlarmSettings.oncePerEpisode ? "once per episode" : "\(minutes(interval)) min"
        }
        let unitName = unit == .millimolesPerLiter ? "mmol/L" : "mg/dL"
        let zones = [
            (LupedAlarmSettings.urgentLowBit, "urgent low"),
            (LupedAlarmSettings.lowBit, "low"),
            (LupedAlarmSettings.highBit, "high"),
        ].filter { alarms.enabledMask & $0.0 != 0 }.map(\.1)
        let time = DateFormatter.localizedString(from: latest.startDate, dateStyle: .none, timeStyle: .medium)
        self.fieldDescription = [
            " 0 protocol version: 1",
            " 1 glucose: \(values[values.count - 1].stringValue) \(unitName)",
            " 2 delta: \(Self.rounded(delta, for: unit).stringValue)",
            " 3 trend: \(Self.directionNames[direction])",
            " 4 history: \(values.count) readings, oldest first: \(values.map(\.stringValue).joined(separator: " "))",
            " 5 unit: \(unitName)",
            " 6-8 thresholds: urgent low \(converted(alarms.urgentLowMgDL).stringValue), low \(converted(alarms.lowMgDL).stringValue), high \(converted(alarms.highMgDL).stringValue)",
            " 9 alarms (mask \(alarms.enabledMask)): \(zones.isEmpty ? "off" : zones.joined(separator: ", "))",
            "10-11 repeat: low \(repeatText(alarms.lowRepeat)), high \(repeatText(alarms.highRepeat))",
            "12 reading time: \(time) (\(timestamp))",
            "13 display: graph",
            "14 urgent-low repeat: \(repeatText(alarms.urgentLowRepeat))",
        ].joined(separator: "\n")
    }

    /// Rounds to the watchface's display precision: one decimal for mmol/L, whole mg/dL.
    ///
    /// `NSDecimalNumber` serializes exactly ("7.9"), whereas a `Double` would
    /// carry binary noise into the JSON ("7.9000000000000004").
    private static func rounded(_ value: Double, for unit: LoopUnit) -> NSDecimalNumber {
        let behavior = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: unit == .millimolesPerLiter ? 1 : 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(value: value).rounding(accordingToBehavior: behavior)
    }

    /// The reading before the latest, if it is recent enough to compare against.
    private static func previousReading(in readings: ArraySlice<StoredGlucoseSample>) -> StoredGlucoseSample? {
        guard readings.count > 1,
              let previous = readings.dropLast().last,
              let latest = readings.last,
              latest.startDate.timeIntervalSince(previous.startDate) <= maximumDeltaInterval
        else {
            return nil
        }
        return previous
    }

    private static func directionIndex(for trend: GlucoseTrend) -> Int {
        switch trend {
        case .downDownDown: return 0 // DoubleDown
        case .downDown: return 1 // SingleDown
        case .down: return 2 // FortyFiveDown
        case .flat: return 3 // Flat
        case .up: return 4 // FortyFiveUp
        case .upUp: return 5 // SingleUp
        case .upUpUp: return 6 // DoubleUp
        }
    }

    /// Fallback for CGMs that do not report a trend.
    private static func directionIndex(from previous: StoredGlucoseSample?, to latest: StoredGlucoseSample) -> Int {
        guard let previous else {
            return 3 // Flat
        }

        let elapsedMinutes = latest.startDate.timeIntervalSince(previous.startDate) / 60
        guard elapsedMinutes > 0 else {
            return 3
        }

        let rate = (latest.quantity.doubleValue(for: .milligramsPerDeciliter)
            - previous.quantity.doubleValue(for: .milligramsPerDeciliter)) / elapsedMinutes

        switch rate {
        case ...(-3): return 0 // DoubleDown
        case ...(-2): return 1 // SingleDown
        case ...(-1): return 2 // FortyFiveDown
        case ..<1: return 3 // Flat
        case ..<2: return 4 // FortyFiveUp
        case ..<3: return 5 // SingleUp
        default: return 6 // DoubleUp
        }
    }
}
#endif
