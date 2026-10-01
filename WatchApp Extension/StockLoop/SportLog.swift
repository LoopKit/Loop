//
//  SportLog.swift
//  WatchApp Extension
//
//  The watch's own log file, and the one function the rest of the app calls to write to it.
//
//  Every field problem on the wrist is diagnosed from this file, so it has to be readable
//  without a Mac: it lives in the app's Documents directory, the diagnostics page tails and
//  shares it, and the session ships a copy to the phone at the moments the analysis cares
//  about. Lines also go to the system log, which is all a distribution build offers.
//
//  Two format rules a future change must not break: every line STARTS with the timestamp, and
//  every SportLog line carries a bracketed `[category]` — that bracket is the grep handle the
//  analysis uses to pull one subsystem's narrative out of the whole file. Add fields to the end
//  of a line rather than reshaping it.
//
//  The file is size-capped, so write MILESTONES — state transitions, grants, hand-backs,
//  verdicts, watchdogs — not per-reading traffic.
//
//  This substrate lives here rather than inside any one subsystem: it is the app's logging
//  infrastructure, and a component that owns it cannot be removed without taking logging away.
//

import Foundation
import os.log
#if os(watchOS)
import WatchKit
#endif

// Milliseconds are load-bearing: most of the questions this log answers are about the ORDER of
// events inside a single burst of radio or queue traffic.
private let logFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

/// One line, one timestamp, both sinks. Stamped HERE rather than at the file write, so the time
/// in the line is when the event happened and not when the writer queue got round to it.
func log(_ items: Any...) {
    let msg = items.map { "\($0)" }.joined(separator: " ")
    let line = "\(logFmt.string(from: Date())) \(msg)"
    NSLog("%@", line)
    LogFile.append(line)
}

/// A fixed-shape battery token, appended to the lines that recur — which is what makes drain
/// correlatable against a stall or a radio failure after the fact. Battery monitoring is off by
/// default, hence the enable on every call; a negative level is watchOS saying it does not know
/// yet, and must read as "?" rather than as a percentage.
func batteryTag() -> String {
    #if os(watchOS)
    let dev = WKInterfaceDevice.current()
    dev.isBatteryMonitoringEnabled = true
    let lvl = dev.batteryLevel
    let st: String
    switch dev.batteryState {
    case .charging:  st = "chg"
    case .full:      st = "full"
    case .unplugged: st = "batt"
    default:         st = "?"
    }
    return lvl < 0 ? "pwr ?/\(st)" : "pwr \(Int(lvl * 100))%/\(st)"
    #else
    return "pwr n/a"
    #endif
}

/// The on-wrist file. Documents, not a cache directory: the diagnostics page shares it, the
/// session transfers it to the phone, and both must be able to reach it after a relaunch.
///
/// Capped at 512 KB and rotated down to 256 KB. The cap is what keeps the watch's storage
/// bounded; the half-file kept back is what makes rotation cheap enough to do inline.
enum LogFile {
    static let url: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("g7watch.log")

    /// Serial, so lines cannot interleave and a `tail` can never read a half-finished rotation.
    private static let queue = DispatchQueue(label: "com.loopkit.Loop.LogFile")
    private static let maxBytes: UInt64 = 512 * 1024
    private static let trimToBytes = 256 * 1024

    /// Never blocks the caller: every call site is on a path — the loop, the radio delegates,
    /// main — where a synchronous file write is exactly what the log is there to catch.
    static func append(_ line: String) {
        guard let url else { return }
        let data = Data((line + "\n").utf8)
        queue.async {
            var size: UInt64 = 0
            if let h = try? FileHandle(forWritingTo: url) {
                size = (try? h.seekToEnd()) ?? 0
                try? h.write(contentsOf: data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
            if size > maxBytes { rotate(url) }
        }
    }

    /// Keeps the NEWEST bytes and discards the partial line at the cut, so the file always starts
    /// on a line boundary — a leading fragment reads as a corrupt first record to anything
    /// parsing the file, including a human.
    private static func rotate(_ url: URL) {
        guard let all = try? Data(contentsOf: url), all.count > trimToBytes else { return }
        var slice = all.suffix(trimToBytes)
        if let nl = slice.firstIndex(of: 0x0a) { slice = slice[slice.index(after: nl)...] }
        try? Data(slice).write(to: url)
    }

    /// What the diagnostics page renders and shares. Runs ON the writer queue so it cannot catch
    /// a rotation in progress, and trims its own leading fragment for the same reason `rotate`
    /// does.
    static func tail(maxBytes: Int = 24 * 1024) -> String {
        return queue.sync {
            guard let url, let all = try? Data(contentsOf: url) else { return "" }
            var slice = all.suffix(maxBytes)
            if all.count > maxBytes, let nl = slice.firstIndex(of: 0x0a) {
                slice = slice[slice.index(after: nl)...]
            }
            return String(decoding: slice, as: UTF8.self)
        }
    }
}

enum SportLog {
    private static let oslog = OSLog(subsystem: "com.loopkit.Loop", category: "SportMode")

    /// `category` becomes the bracketed grep handle in the file (`[loan]`, `[glance]`, `[wc]`,
    /// `[runtime]`, …). Keep an existing category's spelling: the analysis pulls a subsystem's
    /// whole narrative by that literal string.
    static func event(_ category: String, _ message: String) {
        os_log("%{public}@ %{public}@", log: oslog, type: .default, category, message)
        log("[\(category)] \(message)")
    }
}
