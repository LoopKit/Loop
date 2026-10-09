//
//  GlanceComplicationSnapshot.swift
//  Loop Complications
//
//  What the Sport glance complication shows: the glance's own numbers, published by the watch app into
//  the shared app group and read by the Loop Complications extension. Compiled into both (and into the
//  watch tests). As ComplicationSnapshot, strings arrive formatted; the widget decides, per moment,
//  which still stand — a value older than 15 min shows a dash, as stock's own complication.
//

import Foundation

struct GlanceComplicationSnapshot: Codable, Equatable {
    /// The reading in the display unit, or the sensor's condition ("LOW", "HIGH").
    var bgText: String?
    var trendSymbol: String?
    /// The glance's colour for the reading; nil when it does not vouch for it (the phone's loop).
    var bgRange: BGRange?
    /// After this the reading, and the eventual computed from it, show a dash.
    var bgStaleAt: Date?
    /// When the sensor took the reading (Big BG shows its age).
    var bgDate: Date?

    var eventualText: String?
    var iobText: String?
    var cobText: String?
    var tempText: String?
    /// After this the loop's values (IOB, COB, temp, eventual) show a dash: the cycle that made them
    /// is older than 15 min.
    var loopValuesStaleAt: Date?

    /// The glance's override line ("🏓 70% 128"), set only while it is active.
    var overrideLabel: String?
    /// The watch holds the pod (a loan); otherwise the phone loops.
    var watchHasPod = false

    /// The loop ring, as ComplicationSnapshot. An open loop always reads fresh (stock's HUD).
    var loopClosed = true
    var loopDate: Date?
    var freshUntil: Date?
    var agingUntil: Date?

    enum BGRange: String, Codable { case low, inRange, high }

    static let dash = "—"

    func freshness(at date: Date) -> ComplicationSnapshot.Freshness {
        guard loopDate != nil else { return .stale }
        guard loopClosed else { return .fresh }
        if let fresh = freshUntil, date <= fresh { return .fresh }
        if let aging = agingUntil, date <= aging { return .aging }
        return .stale
    }

    private func standing(_ text: String?, until staleAt: Date?, at date: Date) -> String? {
        guard let staleAt, date <= staleAt else { return nil }
        return text
    }

    func bg(at date: Date) -> String? { standing(bgText, until: bgStaleAt, at: date) }
    func trend(at date: Date) -> String { bg(at: date) == nil ? "" : (trendSymbol ?? "") }
    func range(at date: Date) -> BGRange? { bg(at: date) == nil ? nil : bgRange }
    func iob(at date: Date) -> String? { standing(iobText, until: loopValuesStaleAt, at: date) }
    func cob(at date: Date) -> String? { standing(cobText, until: loopValuesStaleAt, at: date) }
    func temp(at date: Date) -> String? { standing(tempText, until: loopValuesStaleAt, at: date) }
    /// Only against a standing reading, as the glance: a prediction from a stale input is not offered.
    func eventual(at date: Date) -> String? {
        bg(at: date) == nil ? nil : standing(eventualText, until: loopValuesStaleAt, at: date)
    }

    /// The moments after `date` at which something visible changes on its own; one timeline entry each.
    func changeMoments(after date: Date) -> [Date] {
        [bgStaleAt, loopValuesStaleAt, loopClosed ? freshUntil : nil, loopClosed ? agingUntil : nil]
            .compactMap { $0?.addingTimeInterval(1) }.filter { $0 > date }
            .reduce(into: [Date]()) { if !$0.contains($1) { $0.append($1) } }.sorted()
    }

    // MARK: - Shared storage (the same app group as ComplicationSnapshot, its own key)

    static let defaultsKey = "GlanceComplicationSnapshot"

    static func load(from defaults: UserDefaults? = ComplicationSnapshot.sharedDefaults) -> GlanceComplicationSnapshot? {
        defaults?.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save(to defaults: UserDefaults? = ComplicationSnapshot.sharedDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults?.set(data, forKey: Self.defaultsKey) }
    }

    // MARK: - Diagnostics: the timelines the widget actually served (confirmation runs C1/C2)

    static let servedKey = "GlanceComplicationServed"

    /// Called by the widget each time it serves a timeline: "epochSeconds metric", newest last, capped.
    /// Fractional seconds: the reload is served within a second of the publish that requested it.
    static func noteServed(_ metric: String, at date: Date = Date(), defaults: UserDefaults? = ComplicationSnapshot.sharedDefaults) {
        guard let defaults else { return }
        var list = defaults.stringArray(forKey: servedKey) ?? []
        list.append("\(date.timeIntervalSince1970) \(metric)")
        if list.count > 200 { list.removeFirst(list.count - 200) }
        defaults.set(list, forKey: servedKey)
    }

    /// The timelines served after `date`, oldest first.
    static func served(after date: Date, defaults: UserDefaults? = ComplicationSnapshot.sharedDefaults) -> [(date: Date, metric: String)] {
        (defaults?.stringArray(forKey: servedKey) ?? []).compactMap { line -> (date: Date, metric: String)? in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let seconds = TimeInterval(parts[0]) else { return nil }
            let at = Date(timeIntervalSince1970: seconds)
            return at > date ? (at, String(parts[1])) : nil
        }
    }

    /// When the widget last built a timeline: the face shows whatever was saved before that.
    static func lastServed(defaults: UserDefaults? = ComplicationSnapshot.sharedDefaults) -> Date? {
        served(after: .distantPast, defaults: defaults).last?.date
    }

    static var sample: GlanceComplicationSnapshot {
        let now = Date()
        return GlanceComplicationSnapshot(bgText: "106", trendSymbol: "↗", bgRange: .inRange,
                                          bgStaleAt: now.addingTimeInterval(15 * 60), bgDate: now,
                                          eventualText: "112",
                                          iobText: "2.3", cobText: "15", tempText: "+0.75",
                                          loopValuesStaleAt: now.addingTimeInterval(15 * 60),
                                          overrideLabel: "🏃 70% 140", watchHasPod: true, loopClosed: true,
                                          loopDate: now, freshUntil: now.addingTimeInterval(6 * 60),
                                          agingUntil: now.addingTimeInterval(16 * 60))
    }
}

/// What the glance complication shows; the widget makes it an App Intent parameter.
enum GlanceMetric: String, CaseIterable {
    case bg, bigBG, bgEventual, eventual, iob, cob, iobCob, temp, loop, override, glance

    /// The face editor's name for the preset (plain String, see the style rules).
    var title: String {
        switch self {
        case .bg: return NSLocalizedString("BG", comment: "Glance complication: glucose")
        case .bigBG: return NSLocalizedString("Big BG", comment: "Glance complication: glucose and trend alone, as large as the slot allows")
        case .bgEventual: return NSLocalizedString("BG → Eventual", comment: "Glance complication: glucose and eventual glucose")
        case .eventual: return NSLocalizedString("Eventual BG", comment: "Glance complication: eventual glucose")
        case .iob: return NSLocalizedString("IOB", comment: "Glance complication: insulin on board")
        case .cob: return NSLocalizedString("COB", comment: "Glance complication: carbs on board")
        case .iobCob: return NSLocalizedString("IOB · COB", comment: "Glance complication: insulin and carbs on board")
        case .temp: return NSLocalizedString("Temp Basal", comment: "Glance complication: net temp basal rate")
        case .loop: return NSLocalizedString("Loop Status", comment: "Glance complication: glucose and loop freshness")
        case .override: return NSLocalizedString("Override", comment: "Glance complication: active override")
        case .glance: return NSLocalizedString("Glance", comment: "Glance complication: the glance's numbers together")
        }
    }
}

// MARK: - Strings

extension GlanceComplicationSnapshot {
    func bgWithTrend(at date: Date) -> String { (bg(at: date) ?? Self.dash) + trend(at: date) }
    private func or(_ text: String?) -> String { text ?? Self.dash }

    /// The labelled line: inline slots, and a corner's curved label.
    func line(_ metric: GlanceMetric, at date: Date, corner: Bool = false) -> String {
        switch metric {
        case .bg, .bigBG, .loop: return corner ? bgWithTrend(at: date) : "BG " + bgWithTrend(at: date)
        case .bgEventual: return bgWithTrend(at: date) + " → " + or(eventual(at: date))
        case .eventual: return (corner ? "EVENTUAL " : NSLocalizedString("Eventually ", comment: "Glance complication inline prefix: eventual glucose")) + or(eventual(at: date))
        case .iob: return "IOB " + or(iob(at: date))
        case .cob: return "COB " + or(cob(at: date))
        case .iobCob: return "IOB " + or(iob(at: date)) + " · COB " + or(cob(at: date))
        case .temp: return (corner ? "TEMP " : "Temp ") + or(temp(at: date))
        case .override: return overrideLabel ?? NSLocalizedString("No override", comment: "Glance complication when no override is active")
        case .glance: return bgWithTrend(at: date) + " · IOB " + or(iob(at: date)) + (corner ? "" : " · COB " + or(cob(at: date)))
        }
    }

    /// The loop's age in whole minutes ("now", "4m", "30m+"), not WidgetKit's ticking relative date
    /// ("33sec"). The timeline carries an entry at each minute mark, which costs no reload budget.
    func loopAge(at date: Date) -> String { Self.age(since: loopDate, at: date) }

    /// The reading's age, as `loopAge`. Empty once the reading shows a dash.
    func bgAge(at date: Date) -> String { bg(at: date) == nil ? "" : Self.age(since: bgDate, at: date) }

    static let loopAgeMinutes = 30

    /// The minute marks after `date` at which `loopAge` changes.
    func loopAgeMarks(after date: Date) -> [Date] { Self.minuteMarks(from: loopDate, after: date) }

    /// The minute marks after `date` at which `bgAge` changes.
    func bgAgeMarks(after date: Date) -> [Date] { Self.minuteMarks(from: bgDate, after: date) }

    private static func age(since start: Date?, at date: Date) -> String {
        guard let start else { return dash }
        let minutes = Int(max(0, date.timeIntervalSince(start)) / 60)
        if minutes < 1 { return "now" }
        return minutes >= loopAgeMinutes ? "\(loopAgeMinutes)m+" : "\(minutes)m"
    }

    private static func minuteMarks(from start: Date?, after date: Date) -> [Date] {
        guard let start else { return [] }
        return (1...loopAgeMinutes).map { start.addingTimeInterval(TimeInterval($0 * 60)) }.filter { $0 > date }
    }

    /// A rectangle's big value.
    func headline(_ metric: GlanceMetric, at date: Date) -> String {
        switch metric {
        case .bg, .bigBG, .loop: return bgWithTrend(at: date)
        case .bgEventual: return line(.bgEventual, at: date)
        default: return value(metric, at: date)
        }
    }

    /// A rectangle's line under the value: BG → eventual, or the loop's numbers when the value is BG.
    func context(_ metric: GlanceMetric, at date: Date) -> String {
        switch metric {
        case .bg, .bigBG, .bgEventual, .eventual, .loop: return line(.iobCob, at: date)
        default: return line(.bgEventual, at: date)
        }
    }

    /// The mini glance's second line and the numbers under it.
    func miniGlanceEventual(at date: Date) -> String { "→ " + or(eventual(at: date)) }
    func miniGlanceNumbers(at date: Date) -> String {
        let iob = "IOB " + or(iob(at: date))
        let cob = "COB " + or(cob(at: date))
        return [iob, cob, or(temp(at: date))].joined(separator: "  ")
    }

    /// The override label split for a circle: its leading symbol, then the rest ("70% 140"). A dash
    /// when no override is active.
    var overrideParts: (symbol: String, rest: String) {
        guard let label = overrideLabel, !label.isEmpty else { return (Self.dash, "") }
        let words = label.split(separator: " ", maxSplits: 1)
        return (String(words[0]), words.count > 1 ? String(words[1]) : "")
    }

    /// A circular slot: a small caption over the value.
    func caption(_ metric: GlanceMetric) -> String {
        switch metric {
        case .bg, .bigBG, .loop, .glance: return ""
        case .bgEventual: return "→"
        case .eventual: return "EVT"
        case .iob: return "IOB"
        case .cob: return "COB"
        case .iobCob: return "IOB·COB"
        case .temp: return "TEMP"
        case .override: return ""
        }
    }

    func value(_ metric: GlanceMetric, at date: Date) -> String {
        switch metric {
        case .bg, .bigBG, .loop, .glance: return or(bg(at: date))
        case .bgEventual, .eventual: return or(eventual(at: date))
        case .iob: return or(iob(at: date))
        case .cob: return or(cob(at: date))
        case .iobCob: return or(iob(at: date)) + "·" + or(cob(at: date))
        case .temp: return or(temp(at: date))
        case .override: return overrideLabel ?? Self.dash
        }
    }
}

/// The glance complication's widget kind, reloaded on its own (WidgetKit budgets reloads per widget).
enum GlanceComplicationKind {
    static let kind = "LoopGlance"
}
