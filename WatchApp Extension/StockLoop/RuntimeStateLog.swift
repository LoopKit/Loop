//
//  RuntimeStateLog.swift
//  WatchApp Extension
//
//  Two instruments that answer the questions a log cannot answer about itself: was the app
//  executing at all, and was the main thread blocked?
//
//  watchOS suspends this app freely, and a suspended process writes nothing — so a log with a
//  four-minute hole is indistinguishable from a quiet, healthy stretch, and a timer that fired
//  minutes late is indistinguishable from one that was scheduled late. The heartbeat turns
//  suspension into a measured number. The stall detector does the same for a wedged main thread,
//  which otherwise produces a completely ordinary-looking log right up to the moment watchOS
//  kills the process and takes the undrained tail with it.
//
//  Both are deliberately SILENT while healthy. Instrumentation that narrates its own health
//  rotates the evidence out of a size-capped file.
//

import Foundation
#if os(watchOS)
import WatchKit
#endif

enum RuntimeStateLog {
    /// Four states, four distinct words. `.inactive` (wrist down, this app still frontmost) and
    /// `.background` (the user is in another app) behave completely differently for runtime and
    /// radio, and collapsing them into one label is what made the original runtime question
    /// unanswerable.
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

    /// The standard tail for a runtime line: app state, keepalive, battery, and Low Power Mode.
    /// Low Power is here because it changes what watchOS will grant, so a run of gaps that begins
    /// when it turns on is a completely different finding from one that does not.
    static func snapshot() -> String {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? " · LOW-POWER" : ""

        return "state \(appStateName()) · \(keepaliveTag()) · \(batteryTag())\(lowPower)"
    }

    private static var timer: DispatchSourceTimer?
    private static var lastTick = Date()

    private static var lastTickState = "unknown"
    private static var lastBackgroundProof = Date.distantPast

    private static let interval: TimeInterval = 30

    /// A healthy tick lands at 30 s plus its leeway, so a gap past 45 s means at least one whole
    /// tick did not run — the app was not executing. Anything tighter reports ordinary timer
    /// jitter as suspension.
    private static let tolerance: TimeInterval = 45

    /// How often a backgrounded-but-alive app is allowed to say so. The positive proof matters
    /// (it is the only evidence that background runtime is actually being granted), but at the
    /// heartbeat's own cadence it would dominate the file.
    private static let backgroundProofInterval: TimeInterval = 120

    /// Supplied by whoever owns the keepalive, so this file does not depend on it. Unset reads
    /// as "?" rather than "not held" — the two mean very different things when a gap is logged.
    static var keepaliveProbe: (() -> String)?

    private static func keepaliveTag() -> String { keepaliveProbe?() ?? "keepalive ?" }

    /// Asks for a short timer and reports how late it was. Silent when it arrives on time —
    /// except for a label containing "start", which always reports so there is a baseline to
    /// compare the late ones against.
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

    // The detector's state is touched from its own utility queue, from main, and from every
    // caller of `mark` — so all of it goes through this lock, and nothing is read outside it.
    private static let stallLock = NSLock()
    private static var pingSentAt: Date?
    private static var stallReportedFor: Date?

    private static var mainMark = "—"
    private static var mainMarkAt = Date()
    private static var lastStallReportAt: Date?

    /// A breadcrumb naming the main-thread entry point about to run. The stall detector can prove
    /// main is wedged but not WHERE; this is the where — the last thing main started and never
    /// finished. Call it before anything on main that could block, not after.
    static func mark(_ label: String) {
        stallLock.lock(); mainMark = label; mainMarkAt = Date(); stallLock.unlock()
    }

    /// Mark a call that BLOCKS, and only when it is main that will do the waiting.
    ///
    /// The gate is not an optimisation. The mark is one shared slot, so a background caller
    /// marking its own blocking read would overwrite main's — and the stall report would name a
    /// call on another thread that was never the problem. Off main this is a thread check and
    /// nothing else.
    ///
    /// Paired with `.done` on the way out so a stall can be attributed to a call still waiting,
    /// rather than to the last one that finished.
    static func markBlockingIfMain(_ label: String) {
        guard Thread.isMainThread else { return }
        mark(label)
    }

    private static let stallThreshold: TimeInterval = 2.0
    private static var stallTimer: DispatchSourceTimer?

    /// Pings main once a second from a UTILITY queue and times the round trip. The queue is the
    /// point: a detector living on main would be wedged by the very thing it exists to report.
    ///
    /// Reports once past the threshold, then again every 10 s while still stuck — a wedge that
    /// lasts minutes must leave evidence throughout, not one line at its start — and reports the
    /// recovery only if the stall was reported, so an ordinary busy moment stays silent.
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

    /// A 30 s tick that writes nothing while the app keeps running, and a GAP line when it does
    /// not. The GAP line names the state the app went DOWN in as well as the one it woke in:
    /// which state suspension started from is the whole question, and the waking state alone
    /// cannot answer it.
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
