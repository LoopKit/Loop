//
//  SportLog.swift
//  WatchApp Extension
//
//  The watch's log file (Documents; tailed and shared by the diagnostics page, sent to the
//  phone). Each line starts with the timestamp and carries a [category]; append fields rather
//  than reshaping lines, and log milestones, not per-reading traffic.
//

import Foundation
import os.log
#if os(watchOS)
import WatchKit
#endif

// Milliseconds: most questions are about ordering within a burst.
private let logFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

/// Stamped at the call, not at the write.
func log(_ items: Any...) {
    let msg = items.map { "\($0)" }.joined(separator: " ")
    let line = "\(logFmt.string(from: Date())) \(msg)"
    NSLog("%@", line)
    LogFile.append(line)
}

/// A fixed-shape battery token for recurring lines; a negative level reads as "?".
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

/// In Documents, capped at 512 KB and rotated to 256 KB.
enum LogFile {
    static let url: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("g7watch.log")

    /// Serial, so lines cannot interleave and a `tail` can never read a half-finished rotation.
    private static let queue = DispatchQueue(label: "com.loopkit.Loop.LogFile")
    private static let maxBytes: UInt64 = 512 * 1024
    private static let trimToBytes = 256 * 1024

    /// Never blocks the caller.
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

    /// Keeps the newest bytes, starting on a line boundary.
    private static func rotate(_ url: URL) {
        guard let all = try? Data(contentsOf: url), all.count > trimToBytes else { return }
        var slice = all.suffix(trimToBytes)
        if let nl = slice.firstIndex(of: 0x0a) { slice = slice[slice.index(after: nl)...] }
        try? Data(slice).write(to: url)
    }

    /// On the writer queue, so it cannot see a rotation in progress.
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

    /// `category` is the grep handle; keep existing spellings.
    static func event(_ category: String, _ message: String) {
        os_log("%{public}@ %{public}@", log: oslog, type: .default, category, message)
        log("[\(category)] \(message)")
    }
}
