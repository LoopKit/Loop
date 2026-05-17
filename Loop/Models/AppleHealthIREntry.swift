//
//  AppleHealthIREntry.swift
//  Loop
//

import Foundation

struct AppleHealthIREntry: Codable, Identifiable {

    static let userDefaultsKey = "appleHealthIRLog"

    let id: UUID
    let timestamp: Date
    let sleepHours: Double?
    let stepCount: Double?
    let hrvSDNN: Double?
    let exerciseMinutes: Double?
    let heartRate: Double?
    let sleepDelta: Double
    let stepsDelta: Double
    let hrvDelta: Double
    let exerciseDelta: Double
    let rhrDelta: Double
    let combinedDelta: Double
    let multiplier: Double
    let thresholdsSnapshot: AppleHealthIRThresholds

    var formattedMultiplier: String {
        String(format: "%.2f\u{00D7}", multiplier)
    }

    static func load() -> [AppleHealthIREntry] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let entries = try? JSONDecoder().decode([AppleHealthIREntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    static func append(_ entry: AppleHealthIREntry) {
        var entries = load()
        entries.append(entry)
        pruneToWindow(86400, entries: &entries)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    static func pruneToWindow(_ window: TimeInterval = 86400) {
        var entries = load()
        pruneToWindow(window, entries: &entries)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private static func pruneToWindow(_ window: TimeInterval, entries: inout [AppleHealthIREntry]) {
        let cutoff = Date().addingTimeInterval(-window)
        entries = entries.filter { $0.timestamp >= cutoff }
    }
}
