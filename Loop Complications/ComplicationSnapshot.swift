//
//  ComplicationSnapshot.swift
//  Loop Complications
//
//  What the watch's complications show, published by the watch app into the shared app group and
//  read by the Loop Complications widget extension. Compiled into both (and into LoopTests). Strings
//  arrive already formatted and localized by the app — the extension links nothing of Loop's — so
//  the widget only decides, per moment, which of them to show.
//

import Foundation

struct ComplicationSnapshot: Codable, Equatable {
    /// The reading, formatted for the display unit, or the sensor's condition ("LOW", "HIGH").
    var glucoseText: String?
    var trendSymbol: String?
    /// Shown in place of the reading once it is stale (stock's localized "---").
    var staleGlucoseText: String = "---"
    /// After this, the reading is stale (stock: reading date + LoopAlgorithm.inputDataRecencyInterval).
    var glucoseStaleAt: Date?
    var eventualText: String?
    /// The wide inline line in stock's localized "UtilitarianLargeFlat" format
    /// ("106↗ 108 8:47 PM"), and the same line with the reading stale.
    var inlineText: String?
    var inlineStaleText: String?
    /// When the loop last completed, and where its colour changes (LoopCompletionFreshness: fresh ≤ 6 min,
    /// aging ≤ 16 min, then stale) — computed by the app so the constants live in one place.
    var loopDate: Date?
    var freshUntil: Date?
    var agingUntil: Date?
    /// What the glucose graph draws; the widget renders it at its slot's size (nil: no graph).
    var graph: ComplicationGraph?

    enum Freshness { case fresh, aging, stale }

    func freshness(at date: Date) -> Freshness {
        guard loopDate != nil else { return .stale }
        if let fresh = freshUntil, date <= fresh { return .fresh }
        if let aging = agingUntil, date <= aging { return .aging }
        return .stale
    }

    func glucoseIsStale(at date: Date) -> Bool {
        glucoseStaleAt.map { date > $0 } ?? true
    }

    /// The reading as shown at `date`: the value, or the stale marker.
    func glucose(at date: Date) -> String {
        glucoseIsStale(at: date) ? staleGlucoseText : (glucoseText ?? staleGlucoseText)
    }

    /// The trend symbol, blank once the reading is stale (as stock).
    func trend(at date: Date) -> String {
        glucoseIsStale(at: date) ? "" : (trendSymbol ?? "")
    }

    func inline(at date: Date) -> String {
        (glucoseIsStale(at: date) ? inlineStaleText : inlineText) ?? glucose(at: date)
    }

    /// The moments after `date` at which something visible changes: the reading goes stale, the loop
    /// colour turns. The widget's timeline carries one entry for each, so no reload is needed for them.
    func changeMoments(after date: Date) -> [Date] {
        [glucoseStaleAt.map { $0.addingTimeInterval(1) }, freshUntil.map { $0.addingTimeInterval(1) },
         agingUntil.map { $0.addingTimeInterval(1) }]
            .compactMap { $0 }.filter { $0 > date }.sorted()
    }

    // MARK: - Shared storage

    static let defaultsKey = "ComplicationSnapshot"

    /// The app group both targets share, from each one's own Info.plist.
    static var appGroupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    }

    static var sharedDefaults: UserDefaults? { appGroupIdentifier.flatMap { UserDefaults(suiteName: $0) } }

    static func load(from defaults: UserDefaults? = sharedDefaults) -> ComplicationSnapshot? {
        defaults?.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save(to defaults: UserDefaults? = Self.sharedDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults?.set(data, forKey: Self.defaultsKey) }
    }

    static var sample: ComplicationSnapshot {
        let now = Date()
        return ComplicationSnapshot(glucoseText: "106", trendSymbol: "↗", glucoseStaleAt: now.addingTimeInterval(15 * 60),
                                    eventualText: "108", inlineText: "106↗ 108", inlineStaleText: "--- 108",
                                    loopDate: now, freshUntil: now.addingTimeInterval(6 * 60),
                                    agingUntil: now.addingTimeInterval(16 * 60), graph: .sample(now: now))
    }
}

/// The glucose graph in the display unit, as plain numbers, so the widget can draw it at its own size.
struct ComplicationGraph: Codable, Equatable {
    struct Point: Codable, Equatable {
        var date: Date
        var value: Double
        var isManual = false
    }

    struct Band: Codable, Equatable {
        var start: Date
        var end: Date
        var min: Double
        var max: Double
    }

    /// The span shown on each side of the moment drawn, as stock's ClockKit graph (4 h centered on now).
    static let halfSpan: TimeInterval = 2 * 60 * 60

    var glucoseMin: Double
    var glucoseMax: Double
    var minLabel: String
    var maxLabel: String
    var targetRanges: [Band]
    /// The active override's target, over its active interval.
    var override: Band?
    var historical: [Point]
    var predicted: [Point]

    static func sample(now: Date) -> ComplicationGraph {
        let historical = (0..<24).map { i in
            Point(date: now.addingTimeInterval(TimeInterval(i - 24) * 300), value: 110 + 25 * sin(Double(i) / 4))
        }
        let predicted = (0..<24).map { i in
            Point(date: now.addingTimeInterval(TimeInterval(i) * 300), value: 120 - Double(i))
        }
        return ComplicationGraph(glucoseMin: 75, glucoseMax: 150, minLabel: "75", maxLabel: "150",
                                 targetRanges: [Band(start: now.addingTimeInterval(-halfSpan), end: now.addingTimeInterval(halfSpan),
                                                     min: 100, max: 110)],
                                 override: nil, historical: historical, predicted: predicted)
    }
}

/// The widget kinds, shared with the watch app (its ClockKit migrator maps old complications to them).
enum LoopComplicationKind {
    static let loopStatus = "LoopStatus"
    static let glucoseGraph = "GlucoseGraph"

    static let all = [loopStatus, glucoseGraph]
}

/// When the watch app should ask WidgetKit for a reload. Reloads are budgeted by the system, so one is
/// requested only when the snapshot changed and at most every `minimumInterval`; a change inside the
/// window is not lost — the owed reload is paid on the next offer once the window has passed.
struct ComplicationReloadThrottle<Snapshot: Equatable> {
    var minimumInterval: TimeInterval = 5 * 60
    private(set) var lastPublished: Snapshot?
    private(set) var lastReloadAt = Date.distantPast
    private(set) var reloadOwed = false

    /// `save`: the snapshot changed and should be written. `reload`: ask WidgetKit now.
    mutating func offer(_ snapshot: Snapshot, now: Date) -> (save: Bool, reload: Bool) {
        let changed = snapshot != lastPublished
        if changed {
            lastPublished = snapshot
            reloadOwed = true
        }
        guard reloadOwed, now.timeIntervalSince(lastReloadAt) >= minimumInterval else { return (changed, false) }
        reloadOwed = false
        lastReloadAt = now
        return (changed, true)
    }
}
