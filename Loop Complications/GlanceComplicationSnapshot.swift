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

/// One value a complication can show. Units and the reading's arrow say what each is; nothing is titled.
enum GlanceValue {
    case bg, age, iob, cob, temp, eventual, override

    /// The face editor's word for it.
    var name: String {
        switch self {
        case .bg: return NSLocalizedString("BG", comment: "Glance complication value: glucose")
        case .age: return NSLocalizedString("Age", comment: "Glance complication value: the reading's age")
        case .iob: return NSLocalizedString("IOB", comment: "Glance complication value: insulin on board")
        case .cob: return NSLocalizedString("COB", comment: "Glance complication value: carbs on board")
        case .temp: return NSLocalizedString("Temp", comment: "Glance complication value: temp basal")
        case .eventual: return NSLocalizedString("Eventual", comment: "Glance complication value: eventual glucose")
        case .override: return NSLocalizedString("Override", comment: "Glance complication value: active override")
        }
    }
}

/// A complication's content, chosen in the face editor. The editor asks for the slot's shape first, so each
/// shape has its own list: the reading always, then whatever fits beside it without shrinking the font, in
/// the order BG; IOB, COB and age; override; temp and who holds the pod; eventual.
enum GlanceOption: String, CaseIterable {
    case cornerAge, cornerIOB, cornerCOB, cornerIOBAge, cornerCOBAge, cornerIOBCOB
    case inlineAge, inlineAgeIOB, inlineAgeCOB, inlineIOBCOB, inlineAll, inlineAllOverride
    case circleAge, circleIOB, circleCOB
    case bigBG, balanced, glance

    enum Shape: String, CaseIterable { case corner, inline, circular, rectangular }

    var shape: Shape {
        switch self {
        case .cornerAge, .cornerIOB, .cornerCOB, .cornerIOBAge, .cornerCOBAge, .cornerIOBCOB: return .corner
        case .inlineAge, .inlineAgeIOB, .inlineAgeCOB, .inlineIOBCOB, .inlineAll, .inlineAllOverride: return .inline
        case .circleAge, .circleIOB, .circleCOB: return .circular
        case .bigBG, .balanced, .glance: return .rectangular
        }
    }

    /// In display order.
    var values: [GlanceValue] {
        switch self {
        case .cornerAge, .inlineAge, .circleAge, .bigBG: return [.bg, .age]
        case .cornerIOB, .circleIOB: return [.bg, .iob]
        case .cornerCOB, .circleCOB: return [.bg, .cob]
        case .cornerIOBAge: return [.bg, .iob, .age]
        case .cornerCOBAge: return [.bg, .cob, .age]
        case .cornerIOBCOB, .inlineIOBCOB: return [.bg, .iob, .cob]
        case .inlineAgeIOB: return [.bg, .age, .iob]
        case .inlineAgeCOB: return [.bg, .age, .cob]
        case .inlineAll, .balanced: return [.bg, .age, .iob, .cob]
        case .inlineAllOverride: return [.bg, .age, .iob, .cob, .override]
        case .glance: return [.bg, .eventual, .age, .iob, .cob, .temp, .override]
        }
    }

    /// A circle's curved bezel label, where the face has one: the IOB, COB and age the circle leaves out,
    /// and an active override.
    var bezelValues: [GlanceValue] {
        [GlanceValue.iob, .cob, .age].filter { !values.contains($0) } + [.override]
    }

    /// The face editor's name for it (plain String, see the style rules).
    var title: String {
        switch self {
        case .bigBG: return NSLocalizedString("Big BG", comment: "Glance complication: the reading as large as the slot allows")
        case .glance: return NSLocalizedString("Glance", comment: "Glance complication: every value of the glance")
        default: return values.map(\.name).joined(separator: " · ")
        }
    }

    static func options(for shape: Shape) -> [GlanceOption] { allCases.filter { $0.shape == shape } }

    /// The saved choice if it belongs to this shape, else the shape's first (an unknown or older name too).
    static func chosen(_ id: String?, for shape: Shape) -> GlanceOption {
        id.flatMap(GlanceOption.init(rawValue:)).flatMap { $0.shape == shape ? $0 : nil } ?? options(for: shape)[0]
    }
}

// MARK: - Strings

extension GlanceComplicationSnapshot {
    func bgWithTrend(at date: Date) -> String { (bg(at: date) ?? Self.dash) + trend(at: date) }
    /// A value as shown, its unit as its label; nil when there is nothing to show (no override, no age).
    /// `capitalised`: the slot draws in capitals (inline, corner), where "4g" would read as "4G".
    func text(_ value: GlanceValue, at date: Date, capitalised: Bool = false) -> String? {
        switch value {
        case .bg: return bgWithTrend(at: date)
        case .age: return bgAge(at: date).isEmpty ? nil : bgAge(at: date)
        case .iob: return (iob(at: date).map { $0 == "-0.0" ? "0.0" : $0 } ?? Self.dash) + "U"
        case .cob: return (cob(at: date) ?? Self.dash) + (capitalised ? " g" : "g")
        case .temp: return (temp(at: date) ?? Self.dash) + "U/h"
        case .eventual: return "→" + (eventual(at: date) ?? Self.dash)
        case .override: return overrideLabel
        }
    }

    /// Several values on one line. The age and the eventual belong to the reading, so they sit beside it;
    /// the rest are set apart with a dot, or only a space where room is tight (a corner).
    func text(_ values: [GlanceValue], at date: Date, tight: Bool = false, capitalised: Bool = false) -> String {
        var line = ""
        for value in values {
            guard let part = text(value, at: date, capitalised: capitalised) else { continue }
            if !line.isEmpty { line += tight || value == .age || value == .eventual ? " " : " · " }
            line += part
        }
        return line
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
}

/// One widget kind per shape, so the face editor offers each shape only its own options. All are reloaded
/// together; watchOS grants one free background reload per app either way.
enum GlanceComplicationKind {
    static func kind(_ shape: GlanceOption.Shape) -> String { "LoopGlance." + shape.rawValue }
    static let all = GlanceOption.Shape.allCases.map(kind)
}
