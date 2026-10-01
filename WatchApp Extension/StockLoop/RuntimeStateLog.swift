//
//  RuntimeStateLog.swift
//  WatchApp Extension
//
//  Was the app running, and was main blocked? A 30 s heartbeat logs suspension gaps; a
//  stall detector logs a wedged main thread. Both silent while healthy.
//

import Foundation
#if os(watchOS)
import WatchKit
#endif

enum RuntimeStateLog {
    /// .inactive and .background behave differently for runtime, so they stay distinct.
    static func appStateName() -> String {
        #if os(watchOS)
        switch WKExtension.shared().applicationState {
        case .active:     return "active"
        case .inactive:   return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
        #else
        return "n/a"
        #endif
    }

    /// App state, keepalive, battery, Low Power Mode.
    static func snapshot() -> String {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? " · LOW-POWER" : ""

        return "state \(appStateName()) · \(keepaliveTag()) · \(batteryTag())\(lowPower)"
    }

    private static var timer: DispatchSourceTimer?
    private static var lastTick = Date()

    private static var lastTickState = "unknown"
    private static var lastBackgroundProof = Date.distantPast

    private static let interval: TimeInterval = 30

    /// A gap past this means at least one tick did not run.
    private static let tolerance: TimeInterval = 45

    /// Rate limit on "alive in background" lines.
    private static let backgroundProofInterval: TimeInterval = 120

    /// Set by the keepalive's owner; unset reads "?".
    static var keepaliveProbe: (() -> String)?

    private static func keepaliveTag() -> String { keepaliveProbe?() ?? "keepalive ?" }

    /// Reports how late a short timer fired; silent when on time, except "start" labels.
    static func probeTimerDeferral(_ label: String, requested: TimeInterval = 3.0,
                                   tolerance: TimeInterval = 1.0) {
        let asked = Date()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + requested) {
            let actual = Date().timeIntervalSince(asked)
            let late = actual - requested
            guard late > tolerance || label.contains("start") else { return }
            SportLog.event("runtime", String(format:
                "timer-probe [%@] asked %.1fs got %.1fs (late %+.1fs) · %@ · %@",
                label, requested, actual, late, keepaliveTag(), snapshot()))
        }
    }

    // All detector state goes through this lock.
    private static let stallLock = NSLock()
    private static var pingSentAt: Date?
    private static var stallReportedFor: Date?

    private static var mainMark = "—"
    private static var mainMarkAt = Date()
    private static var lastStallReportAt: Date?

    /// Names the main-thread call about to run, so a stall report can say where.
    static func mark(_ label: String) {
        stallLock.lock(); mainMark = label; mainMarkAt = Date(); stallLock.unlock()
    }

    /// Only on main: the mark is one shared slot. Paired with `.done`.
    static func markBlockingIfMain(_ label: String) {
        guard Thread.isMainThread else { return }
        mark(label)
    }

    private static let stallThreshold: TimeInterval = 2.0
    private static var stallTimer: DispatchSourceTimer?

    /// Times a ping to main from a utility queue; reports past the threshold, every 10 s while
    /// stuck, and the recovery.
    static func startMainStallDetector() {
        stopMainStallDetector()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(200))
        t.setEventHandler {
            stallLock.lock()
            let outstanding = pingSentAt
            let alreadyReported = stallReportedFor
            stallLock.unlock()

            if let sent = outstanding {
                let stuckFor = Date().timeIntervalSince(sent)
                if stuckFor > stallThreshold, alreadyReported != sent {
                    stallLock.lock()
                    stallReportedFor = sent

                    lastStallReportAt = Date()
                    let where_ = mainMark
                    let markAge = Date().timeIntervalSince(mainMarkAt)
                    stallLock.unlock()
                    SportLog.event("runtime", String(format:
                        "MAIN STALLED — main thread has not run for %.1fs (still stuck) · last main entry: %@ (%.1fs ago) · %@",
                        stuckFor, where_, markAge, keepaliveTag()))
                }

                else if stuckFor > stallThreshold, let last = lastStallReportAt,
                        Date().timeIntervalSince(last) >= 10 {
                    stallLock.lock()
                    lastStallReportAt = Date()
                    let where_ = mainMark
                    stallLock.unlock()
                    SportLog.event("runtime", String(format:
                        "MAIN STILL STALLED — %.0fs and counting · last main entry: %@", stuckFor, where_))
                }
                return
            }

            let sent = Date()
            stallLock.lock(); pingSentAt = sent; stallLock.unlock()
            DispatchQueue.main.async {
                let waited = Date().timeIntervalSince(sent)
                stallLock.lock()
                pingSentAt = nil
                let wasReported = (stallReportedFor == sent)
                if wasReported { stallReportedFor = nil }
                stallLock.unlock()

                if wasReported {
                    SportLog.event("runtime", String(format: "MAIN RECOVERED — main was blocked for %.1fs", waited))
                }
            }
        }
        t.resume()
        stallTimer = t
    }

    static func stopMainStallDetector() {
        stallTimer?.cancel()
        stallTimer = nil
        stallLock.lock(); pingSentAt = nil; stallReportedFor = nil; stallLock.unlock()
    }

    /// Silent while running; a GAP line names the state the app went down in and woke in.
    static func startHeartbeat() {
        stopHeartbeat()
        lastTick = Date()
        lastTickState = appStateName()
        lastBackgroundProof = .distantPast
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(2))
        t.setEventHandler {
            let now = Date()
            let gap = now.timeIntervalSince(lastTick)
            let wentDownIn = lastTickState
            lastTick = now
            let state = appStateName()
            lastTickState = state

            if gap > tolerance {
                SportLog.event("runtime", String(format:
                    "GAP %.0fs (expected %.0fs) — app was NOT executing · went down in state %@ · woke in %@ · %@ · %@",
                    gap, interval, wentDownIn, state, keepaliveTag(), snapshot()))
                return
            }

            if state == "background", now.timeIntervalSince(lastBackgroundProof) >= backgroundProofInterval {
                lastBackgroundProof = now
                SportLog.event("runtime", "BG-ALIVE — executing while backgrounded · \(keepaliveTag()) · \(snapshot())")
            }
        }
        t.resume()
        timer = t
        SportLog.event("runtime", "heartbeat armed (30s; gaps >45s + BG-ALIVE every 2min while backgrounded) · \(keepaliveTag()) · \(snapshot())")
    }

    static func stopHeartbeat() {
        timer?.cancel()
        timer = nil
    }
}
