//
//  DeviceLogThrottle.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  Counts repeated device-log lines instead of writing them; the count rides the next distinct line.
//

import Foundation

/// Called from several queues at once, so all state is behind the lock.
final class DeviceLogThrottle {
    static let window: TimeInterval = 2.0

    enum Verdict: Equatable {
        /// Write this line, and say that `flushing` identical lines were suppressed before it.
        case write(flushing: Int)

        case suppress
    }

    private let lock = NSLock()
    private var lastLine = ""
    private var lastAt = Date.distantPast
    private var suppressedCount = 0

    func admit(_ line: String, at now: Date) -> Verdict {
        lock.lock()
        defer { lock.unlock() }

        if line == lastLine, now.timeIntervalSince(lastAt) < Self.window {
            suppressedCount += 1

            // The window SLIDES from the most recent repeat, so a continuous storm stays
            // collapsed for as long as it lasts rather than leaking a line every two seconds.
            lastAt = now
            return .suppress
        }

        let flushing = suppressedCount
        suppressedCount = 0
        lastLine = line
        lastAt = now
        return .write(flushing: flushing)
    }
}
