//
//  DeviceLogThrottle.swift
//  WatchApp Extension
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//
//  Collapses a repeating device-log line instead of writing it.
//
//  A retrying radio can emit thousands of identical lines per second, and each one costs a
//  synchronous NSLog plus a file append: main starves, and every piece of real evidence rotates
//  out of the size-capped log inside a second. Repeats are counted rather than written, and the
//  count is stated on the next line that differs — a suppressed line is never lost silently.
//

import Foundation

/// Shared by the CGM manager and the pump manager through one device-log delegate, which is
/// called from several queues at once during exactly the storms this exists for — so all of the
/// state is behind the lock.
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
