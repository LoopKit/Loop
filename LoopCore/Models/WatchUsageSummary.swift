//
//  WatchUsageSummary.swift
//  LoopCore
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

public struct ForegroundSessions: Codable, Equatable, Sendable {
    public var count = 0
    public var duration: TimeInterval = 0
    public var maxDuration: TimeInterval = 0
    public var under10sCount = 0
    public var from10To60sCount = 0
    public var from1To5MinCount = 0
    public var over5MinCount = 0

    public init() {}

    public mutating func add(duration: TimeInterval) {
        count += 1
        self.duration += duration
        maxDuration = max(maxDuration, duration)
        switch duration {
        case ..<10:
            under10sCount += 1
        case ..<60:
            from10To60sCount += 1
        case ..<300:
            from1To5MinCount += 1
        default:
            over5MinCount += 1
        }
    }

    /// Keys are `<prefix>Count`, `<prefix>Seconds`, `max<Prefix>Seconds` and `<prefix>Under10sCount` etc.
    public func properties(prefix: String) -> [String: Any] {
        let capitalized = prefix.prefix(1).uppercased() + prefix.dropFirst()
        return [
            "\(prefix)Count": count,
            "\(prefix)Seconds": Int(duration),
            "max\(capitalized)Seconds": Int(maxDuration),
            "\(prefix)Under10sCount": under10sCount,
            "\(prefix)10To60sCount": from10To60sCount,
            "\(prefix)1To5MinCount": from1To5MinCount,
            "\(prefix)Over5MinCount": over5MinCount
        ]
    }
}

public struct WatchUsageSummary: Codable, Equatable, Sendable {
    public var day: Date
    public var utcOffset = TimeZone.current.secondsFromGMT()
    public var foreground = ForegroundSessions()
    public var complicationLaunchCount = 0
    public var notificationResponseCount = 0
    public var screenCounts: [String: Int] = [:]

    public init(day: Date) {
        self.day = day
    }

    public var properties: [String: Any] {
        var properties = foreground.properties(prefix: "watchForeground")
        properties["day"] = ISO8601DateFormatter.string(from: day, timeZone: TimeZone(secondsFromGMT: utcOffset) ?? .current, formatOptions: .withFullDate)
        properties["utcOffset"] = utcOffset
        properties["watchComplicationLaunchCount"] = complicationLaunchCount
        properties["watchNotificationResponseCount"] = notificationResponseCount
        properties["watchScreenCounts"] = screenCounts
        return properties
    }
}

public struct WatchUsageSummaryUserInfo {
    let version = 1
    public let summary: WatchUsageSummary

    public init(summary: WatchUsageSummary) {
        self.summary = summary
    }
}

extension WatchUsageSummaryUserInfo: RawRepresentable {
    public typealias RawValue = [String: Any]

    public static let name = "WatchUsageSummaryUserInfo"

    public init?(rawValue: RawValue) {
        guard
            rawValue["v"] as? Int == version,
            let data = rawValue["s"] as? Data,
            let summary = try? JSONDecoder().decode(WatchUsageSummary.self, from: data)
        else {
            return nil
        }
        self.summary = summary
    }

    public var rawValue: RawValue {
        return [
            "v": version,
            "name": WatchUsageSummaryUserInfo.name,
            "s": (try? JSONEncoder().encode(summary)) ?? Data()
        ]
    }
}

/// Keeps a daily summary of watch app use and hands each completed day to `sendSummary`, which returns false to retry later.
@MainActor
public final class WatchUsageRecorder {

    private let defaults: UserDefaults
    private let sendSummary: (WatchUsageSummary) -> Bool

    private var activeStart: Date?

    public init(defaults: UserDefaults = .standard, sendSummary: @escaping (WatchUsageSummary) -> Bool) {
        self.defaults = defaults
        self.sendSummary = sendSummary
    }

    public func didBecomeActive(at date: Date = Date()) {
        activeStart = date
        update(now: date) { _ in }
    }

    public func willResignActive(at date: Date = Date()) {
        guard let activeStart else {
            return
        }
        self.activeStart = nil
        let duration = max(0, date.timeIntervalSince(activeStart))
        update(now: date) { $0.foreground.add(duration: duration) }
    }

    public func didLaunchFromComplication() {
        update { $0.complicationLaunchCount += 1 }
    }

    public func didRespondToNotification() {
        update { $0.notificationResponseCount += 1 }
    }

    public func didDisplayScreen(_ name: String) {
        update { $0.screenCounts[name, default: 0] += 1 }
    }

    public func sendCompletedDays() {
        var pending = pendingSummaries
        while let summary = pending.first, sendSummary(summary) {
            pending.removeFirst()
        }
        pendingSummaries = pending
    }

    private func update(now: Date = Date(), _ change: (inout WatchUsageSummary) -> Void) {
        let day = Calendar.current.startOfDay(for: now)
        var summary = currentSummary ?? WatchUsageSummary(day: day)

        if summary.day != day {
            pendingSummaries = Array((pendingSummaries + [summary]).suffix(Self.maxPendingDays))
            summary = WatchUsageSummary(day: day)
        }

        change(&summary)
        currentSummary = summary
        sendCompletedDays()
    }

    private static let maxPendingDays = 14
    private static let currentSummaryKey = "com.loopkit.Loop.WatchUsageSummary"
    private static let pendingSummariesKey = "com.loopkit.Loop.WatchUsagePendingSummaries"

    public private(set) var currentSummary: WatchUsageSummary? {
        get { defaults.data(forKey: Self.currentSummaryKey).flatMap { try? JSONDecoder().decode(WatchUsageSummary.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.currentSummaryKey) }
    }

    public private(set) var pendingSummaries: [WatchUsageSummary] {
        get { defaults.data(forKey: Self.pendingSummariesKey).flatMap { try? JSONDecoder().decode([WatchUsageSummary].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.pendingSummariesKey) }
    }
}
