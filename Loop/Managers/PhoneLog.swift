//
//  PhoneLog.swift
//  Loop
//
//  The phone's own field log — the counterpart to the watch's SportLog, and the only record of
//  what this side of a loan did. os_log alone is unreadable without a sysdiagnose, and a loan
//  question ("did the phone actually release the pod?") needs both devices' accounts side by
//  side.
//
//  Lines append to a local file immediately, which is cheap; the iCloud mirror is throttled,
//  because url(forUbiquityContainerIdentifier:) can block. Named g7phone-*.log so it lands
//  beside the watch's g7watch-*.log in the same container.
//

import Foundation
import os.log

enum PhoneLog {
    private static let oslog = OSLog(subsystem: "com.loopkit.Loop", category: "PhoneLog")

    /// Serial, and every append and mirror runs on it. Concurrent mirrors interleave their
    /// copy and replace steps, which leaves the mirrored file missing rather than merely stale.
    private static let queue = DispatchQueue(label: "com.loopkit.Loop.phoneLog", qos: .utility)
    private static var lastMirror = Date.distantPast

    /// Ceiling on how often the container is touched. `flush()` is how a caller overrides it at
    /// a moment worth capturing.
    private static let mirrorInterval: TimeInterval = 60

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Writes one line, to the system log and to the file. The category is a short tag the field
    /// analysis greps on, so keep existing ones stable rather than renaming them.
    static func event(_ category: String, _ message: String) {
        os_log("%{public}@ %{public}@", log: oslog, type: .default, category, message)
        let line = "\(stamp.string(from: Date())) [\(category)] \(message)"
        queue.async {
            appendLocally(line)
            if Date().timeIntervalSince(lastMirror) > mirrorInterval {
                lastMirror = Date()
                mirrorToICloud()
            }
        }
    }

    /// Mirror now, skipping the throttle. Used at the few moments the analysis cares about —
    /// a mirror that arrives a minute later has usually already been overtaken by the event
    /// being investigated.
    static func flush() {
        queue.async {
            lastMirror = Date()
            mirrorToICloud()
        }
    }

    private static var localURL: URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("g7phone-latest.log")
    }

    /// Rotate at 2 MB down to 1 MB. Trimming well below the cap keeps rotation rare; trimming
    /// to just under it would rewrite the whole file on almost every append.
    private static let maxBytes: UInt64 = 2 * 1024 * 1024
    private static let trimToBytes = 1024 * 1024

    /// Appends through a file handle, falling back to creating the file. Every failure is
    /// swallowed: losing a diagnostic line must never disturb the loan it is describing.
    private static func appendLocally(_ line: String) {
        guard let url = localURL else { return }
        let data = Data((line + "\n").utf8)
        var size: UInt64 = 0
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            size = (try? handle.seekToEnd()) ?? 0
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
        if size > maxBytes { rotate(url) }
    }

    private static func rotate(_ url: URL) {
        guard let all = try? Data(contentsOf: url), all.count > trimToBytes else { return }
        var slice = all.suffix(trimToBytes)
        // Drop the partial first line so the file always starts on a record boundary.
        if let nl = slice.firstIndex(of: 0x0a) { slice = slice[slice.index(after: nl)...] }
        try? Data(slice).write(to: url)
    }

    private static func mirrorToICloud() {
        let fm = FileManager.default
        guard let local = localURL, fm.fileExists(atPath: local.path) else { return }
        guard let container = fm.url(forUbiquityContainerIdentifier: nil) else { return }
        let dir = container.appendingPathComponent("Documents", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Copy to a sibling and replace in one step. Removing the published file first leaves a
        // window in which there is no log in the container at all.
        let cloudLatest = dir.appendingPathComponent("g7phone-latest.log")
        let tmp = dir.appendingPathComponent(".g7phone-latest.tmp")
        try? fm.removeItem(at: tmp)
        if (try? fm.copyItem(at: local, to: tmp)) != nil {
            _ = try? fm.replaceItemAt(cloudLatest, withItemAt: tmp)
        }
    }
}
