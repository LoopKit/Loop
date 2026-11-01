//
//  LoopHistoryModels.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm

/// Plain value types the redesigned screens draw from. Glucose is kept in mg/dL and converted only for display,
/// so the statistics don't depend on the display unit.

struct GlucosePoint: Equatable {
    let date: Date
    let mgdl: Double
    /// A fingerstick or other reading typed in: drawn on charts, but left out of CGM statistics.
    var userEntered = false
}

struct BolusEvent: Equatable, Identifiable {
    let id: String
    let date: Date
    let units: Double
    /// Issued by Loop (automatic bolus) rather than by the person.
    let automatic: Bool
    /// Logged in Loop by hand rather than delivered by the pump; these can be deleted.
    let manuallyEntered: Bool
    /// Kept so a manually entered dose can be deleted from the dose store.
    var dose: DoseEntry? = nil
    /// False when the record doesn't say whether Loop or the person gave it, such as another app's doses in Apple Health.
    var automaticKnown = true

    static func == (lhs: BolusEvent, rhs: BolusEvent) -> Bool {
        lhs.id == rhs.id && lhs.date == rhs.date && lhs.units == rhs.units && lhs.automatic == rhs.automatic
    }
}

struct BasalSegment: Equatable {
    enum Kind: Equatable {
        /// The scheduled rate, with no temp basal running.
        case scheduled
        /// A temp basal, set by Loop or by hand.
        case temp
        case suspended
    }

    let start: Date
    let end: Date
    /// The rate actually delivered, in U/h.
    let rate: Double
    /// The profile rate at the time, in U/h, if known.
    let scheduledRate: Double?
    let kind: Kind
    let automatic: Bool

    var hours: Double { end.timeIntervalSince(start) / 3600 }
    var units: Double { rate * hours }
    /// Units delivered above (positive) or below (negative) the schedule.
    var netUnits: Double {
        guard let scheduledRate else { return 0 }
        return (rate - scheduledRate) * hours
    }

    func clamped(to interval: DateInterval) -> BasalSegment? {
        let s = max(start, interval.start), e = min(end, interval.end)
        guard e > s else { return nil }
        return BasalSegment(start: s, end: e, rate: rate, scheduledRate: scheduledRate, kind: kind, automatic: automatic)
    }
}

struct ScheduledBasalPoint: Equatable {
    let start: Date
    let end: Date
    let rate: Double
}

/// The correction range over part of a chart, in mg/dL.
struct TargetBand: Equatable {
    let start: Date
    let end: Date
    let range: ClosedRange<Double>
}

struct CarbEvent: Equatable, Identifiable {
    let id: String
    let date: Date
    let grams: Double
    let absorptionHours: Double?
    let foodType: String?
    let createdByLoop: Bool
    /// Kept so the entry can be edited or deleted.
    var entry: StoredCarbEntry? = nil

    static func == (lhs: CarbEvent, rhs: CarbEvent) -> Bool {
        lhs.id == rhs.id && lhs.date == rhs.date && lhs.grams == rhs.grams
    }
}

struct TimedValue: Equatable {
    let date: Date
    let value: Double
}

struct PumpLogEvent: Equatable, Identifiable {
    enum Kind: Equatable {
        case siteChange(String)
        case alarm(String)
        case resume
    }

    let id: String
    let date: Date
    let kind: Kind
}

/// Everything known about one day or reporting period, for InsulinTimeline and the Now screen.
struct DayHistory {
    var window: DateInterval
    var glucose: [GlucosePoint] = []
    var boluses: [BolusEvent] = []
    var basal: [BasalSegment] = []
    var scheduledBasal: [ScheduledBasalPoint] = []
    var carbs: [CarbEvent] = []
    var iob: [TimedValue] = []
    var cob: [TimedValue] = []
    /// Where the data came from, so older days can say they are missing Loop's own detail.
    var source: HistorySource = .loop

    var bolusUnits: Double { boluses.reduce(0) { $0 + $1.units } }
    var basalUnits: Double { basal.reduce(0) { $0 + $1.units } }
    var carbGrams: Double { carbs.reduce(0) { $0 + $1.grams } }
    var totalUnits: Double { bolusUnits + basalUnits }
    var insulinSplit: InsulinSplit { InsulinSplit(basal: basalUnits, boluses: boluses) }

    /// Only what falls inside `interval`, with basal cut at its edges.
    func clipped(to interval: DateInterval) -> DayHistory {
        var history = self
        let inside: (Date) -> Bool = { $0 >= interval.start && $0 < interval.end }
        history.window = interval
        history.glucose = glucose.filter { inside($0.date) }
        history.boluses = boluses.filter { inside($0.date) }
        history.basal = basal.compactMap { $0.clamped(to: interval) }
        history.carbs = carbs.filter { inside($0.date) }
        history.iob = iob.filter { inside($0.date) }
        history.cob = cob.filter { inside($0.date) }
        return history
    }
}

/// Basal and bolus for one day, or averaged per day, with bolus split into manual and automatic.
struct InsulinSplit: Equatable {
    var basal = 0.0
    var manualBolus = 0.0
    var automaticBolus = 0.0
    /// Bolus that doesn't say whether it was manual or automatic; while there is any, the split isn't shown.
    var unclassifiedBolus = 0.0

    var bolus: Double { manualBolus + automaticBolus + unclassifiedBolus }
    var total: Double { basal + bolus }
    var isClassified: Bool { unclassifiedBolus < 0.005 }

    /// Shares in whole percent that add up to 100.
    var bolusPercent: Int { total > 0 ? Int((bolus / total * 100).rounded()) : 0 }
    var basalPercent: Int { total > 0 ? 100 - bolusPercent : 0 }
}

extension InsulinSplit {
    init(basal: Double, boluses: [BolusEvent]) {
        self.basal = basal
        for bolus in boluses {
            if !bolus.automaticKnown {
                unclassifiedBolus += bolus.units
            } else if bolus.automatic {
                automaticBolus += bolus.units
            } else {
                manualBolus += bolus.units
            }
        }
    }

    /// The per-day average of several days' splits.
    static func average(_ splits: [InsulinSplit]) -> InsulinSplit {
        guard !splits.isEmpty else { return InsulinSplit() }
        let n = Double(splits.count)
        return InsulinSplit(basal: splits.reduce(0) { $0 + $1.basal } / n,
                            manualBolus: splits.reduce(0) { $0 + $1.manualBolus } / n,
                            automaticBolus: splits.reduce(0) { $0 + $1.automaticBolus } / n,
                            unclassifiedBolus: splits.reduce(0) { $0 + $1.unclassifiedBolus } / n)
    }
}

enum HistorySource {
    /// Loop's own stores: manual versus automatic, temp basals and the schedule are all known.
    case loop
    /// Apple Health, for days older than Loop keeps. Doses are split into basal and bolus only.
    case health
}

/// One stretch of the period in a single loop mode.
struct LoopModeSpan: Equatable {
    enum Mode: Equatable {
        case closed
        case limited
        case open
    }

    let start: Date
    let end: Date
    let mode: Mode
    let cause: String?

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

// MARK: - Glucose unit

struct GlucoseUnitStyle: Equatable {
    let isMmol: Bool

    init(unit: LoopUnit) {
        isMmol = unit == .millimolesPerLiter
    }

    init(isMmol: Bool) {
        self.isMmol = isMmol
    }

    static let mgdlPerMmol = 18.0182

    var unitName: String { isMmol ? "mmol/L" : "mg/dL" }

    func value(_ mgdl: Double) -> Double { isMmol ? mgdl / Self.mgdlPerMmol : mgdl }
    func mgdl(_ displayValue: Double) -> Double { isMmol ? displayValue * Self.mgdlPerMmol : displayValue }

    func format(_ mgdl: Double) -> String {
        isMmol ? LoopFormat.number(mgdl / Self.mgdlPerMmol, decimals: 1) : LoopFormat.number(mgdl, decimals: 0)
    }

    /// Fixed chart scales from the design: 2–20 mmol/L on day views, 0–22 on AGP.
    var dayDomain: ClosedRange<Double> { isMmol ? 2...20 : 36...360 }
    var agpDomain: ClosedRange<Double> { isMmol ? 0...22 : 0...400 }
    var dayTicks: [Double] { isMmol ? [4, 10, 16] : [70, 180, 300] }
    var agpTicks: [Double] { isMmol ? [0, 4, 10, 16, 22] : [0, 70, 180, 250, 400] }
}

// MARK: - Formatting

enum LoopFormat {
    /// A number in the user's locale, e.g. "7.3" or "7,3", with no grouping so values read like Loop's own screens.
    static func number(_ value: Double, decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).grouping(.never))
    }

    static func doseUnits(_ units: Double) -> String {
        String(format: NSLocalizedString("%1$@ U", comment: "Format string for an amount of insulin in units. (1: amount)"), number(units, decimals: 2))
    }

    static func totalUnits(_ units: Double) -> String {
        String(format: NSLocalizedString("%1$@ U", comment: "Format string for an amount of insulin in units. (1: amount)"), number(units, decimals: 1))
    }

    static func rate(_ rate: Double) -> String {
        String(format: NSLocalizedString("%1$@ U/h", comment: "Format string for an insulin rate in units per hour. (1: rate)"), number(rate, decimals: 2))
    }

    static func grams(_ grams: Double) -> String {
        String(format: NSLocalizedString("%1$@ g", comment: "Format string for an amount of carbohydrate in grams. (1: grams)"), number(grams, decimals: 0))
    }

    static func signed(_ value: Double, decimals: Int = 2) -> String {
        let s = number(abs(value), decimals: decimals)
        if abs(value) < pow(10, -Double(decimals)) / 2 { return "+" + s }
        return (value < 0 ? "−" : "+") + s
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "25 Oct 2026"
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "Sun 25 Oct"
    static func weekdayDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "12 – 25 Oct 2026", "28 Sep – 25 Oct 2026", "20 Dec 2025 – 2 Jan 2026", in the user's locale.
    static func range(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(start, inSameDayAs: end) {
            return day(end)
        }
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.dateTemplate = "dMMMy"
        return formatter.string(from: start, to: end)
    }

    /// "13d 11h", "9h 45m", "40m" in English; abbreviated in the user's language.
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = minutes >= 1440 ? [.day, .hour] : minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes * 60)) ?? ""
    }

    /// "2m", "1h 5m": how long ago, for the status pill.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = minutes >= 1440 ? [.day, .hour] : minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = minutes == 0 ? .pad : .dropAll
        return formatter.string(from: TimeInterval(minutes * 60)) ?? ""
    }
}

// MARK: - Store conversion boundaries

extension BolusEvent {
    init?(dose: DoseEntry, in interval: DateInterval) {
        guard dose.type == .bolus, dose.startDate >= interval.start, dose.startDate < interval.end else { return nil }
        self.init(id: dose.syncIdentifier ?? "\(dose.startDate.timeIntervalSince1970)", date: dose.startDate,
                  units: dose.unitsInDeliverableIncrements, automatic: dose.automatic ?? false,
                  manuallyEntered: dose.manuallyEntered, dose: dose)
    }
}

extension LoopHistoryMath.BasalDelivery {
    init?(dose: DoseEntry) {
        let kind: BasalSegment.Kind
        switch dose.type {
        case .basal: kind = .scheduled
        case .tempBasal: kind = .temp
        case .suspend: kind = .suspended
        default: return nil
        }
        let hours = dose.endDate.timeIntervalSince(dose.startDate) / 3600
        guard hours > 0 else { return nil }
        self.init(start: dose.startDate, end: dose.endDate,
                  rate: kind == .suspended ? 0 : dose.unitsInDeliverableIncrements / hours,
                  kind: kind, automatic: dose.automatic ?? (kind == .temp))
    }
}

extension BasalSegment {
    init?(healthSample sample: HKQuantitySample, in interval: DateInterval) {
        let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
        guard hours > 0 else { return nil }
        let scheduled = (sample.metadata?["com.loopkit.InsulinKit.MetadataKeyScheduledBasalRate"] as? HKQuantity)?
            .doubleValue(for: HKUnit.internationalUnit().unitDivided(by: .hour()))
        let segment = BasalSegment(start: sample.startDate, end: sample.endDate,
                                   rate: sample.quantity.doubleValue(for: .internationalUnit()) / hours,
                                   scheduledRate: scheduled, kind: .temp,
                                   automatic: (sample.metadata?["com.loopkit.InsulinKit.MetadataKeyAutomaticallyIssued"] as? NSNumber)?.boolValue ?? false)
        guard let clamped = segment.clamped(to: interval) else { return nil }
        self = clamped
    }
}
