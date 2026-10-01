//
//  LoanDebugView.swift
//  WatchApp
//
//  The Sport Mode diagnostics page: a TabView page beside the glance, showing the loop's and the
//  loan's internals and offering the log.
//
//  It is a READER. Everything on it comes from the published mirrors, never from a synchronous
//  read of the loop or loan queues — see `tick`. The few controls act through the loan
//  controller or the CGM manager, or flip a stored flag another component reads later.
//

import Foundation
import SwiftUI
import WatchKit
import WatchConnectivity
import HealthKit
import LoopKit
import G7SensorKit

/// A snapshot of the CGM manager's own view of its sensor, taken whole at tick time so the CGM
/// rows all describe one instant instead of drifting apart as the body re-evaluates.
struct CGMHealth {
    let sensorName: String?
    let lastReadingAge: TimeInterval?

    let bgLine: String
    let linkState: String
    let lifecycle: String
    let expiresIn: String

    init(_ manager: G7CGMManager) {
        sensorName = manager.sensorName
        lastReadingAge = manager.latestReadingTimestamp.map { Date().timeIntervalSince($0) }
        if let g = manager.latestReading?.glucose, let t = manager.latestReadingTimestamp {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            bgLine = String(format: "%d mg/dL · %@ (%.0fs ago)", Int(g), f.string(from: t), Date().timeIntervalSince(t))
        } else {
            bgLine = "—"
        }

        linkState = manager.isConnected ? "connected" : (manager.isScanning ? "scanning" : "idle")
        lifecycle = String(describing: manager.lifecycleState)
        if let expiry = manager.sensorExpiresAt {
            let hours = expiry.timeIntervalSinceNow / 3600
            expiresIn = hours > 0 ? String(format: "%.1f h", hours) : "expired"
        } else {
            expiresIn = "—"
        }
    }
}

struct LoanDebugView: View {
    @State private var snapshot: PodLoanWatchController.DebugSnapshot?
    @State private var cgm: CGMHealth?
    @State private var lastAction: String = "—"

    @State private var iobText: String = "—"

    @State private var dosing: WatchLoopManager.GlanceData?
    @State private var cobText: String = "—"

    // Read by G7SensorKit's Bluetooth manager (`G7BluetoothManager.relodgeKey`), which is a
    // different module — so this literal is the whole contract between them, and it is only
    // consulted when the link next closes.
    @AppStorage("G7Lab.relodge") private var relodge = "holdApp"

    // Same defaults key as `StockLoopSession.loanWorkoutKey`, spelled out twice. Change one and
    // the toggle silently stops reaching the thing it toggles.
    @AppStorage("G7Lab.loan.workout") private var loanWorkout = false

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// Always `sharedIfAvailable()`, never `WKApplication.shared().delegate` — under the SwiftUI
    /// lifecycle that property is always nil, and a control wired through it is silently inert
    /// with no error anywhere. Nil here simply means Sport Mode is unavailable, and every row
    /// keeps its previous value rather than blanking.
    private var session: StockLoopSession? {
        ExtensionDelegate.sharedIfAvailable()?.stockLoopSession
    }

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("build \(BuildDetails.default.codeIdentity)")
                    .font(.footnote).foregroundColor(.secondary)
                Text("DOSING").font(.footnote).foregroundColor(.secondary)
                row("closed?", (dosing?.closedLoopEnabled ?? false) ? "YES" : "no")
                row("BG now", dosing?.glucose.map { String(format: "%.0f", $0.doubleValue(for: .milligramsPerDeciliter)) } ?? "—")
                row("eventual", dosing?.eventual.map { String(format: "%.0f", $0.doubleValue(for: .milligramsPerDeciliter)) } ?? "—")
                predictionReconciliation
                row("COB / IOB", "\(cobText) / \(dosing?.iob.map { String(format: "%.2f U", $0) } ?? "—")")
                row("recommend", dosing?.recommendedTempRate.map { String(format: "%+.2f U/hr", $0) } ?? "—")
                row("running", dosing?.tempRate.map { String(format: "%+.2f U/hr net", $0) } ?? "none (scheduled)")
                row("last loop", dosing?.lastLoopCompleted.map { String(format: "%.0fs ago", Date().timeIntervalSince($0)) } ?? "—")
                if let err = dosing?.lastLoopErrorText { row("loop err", err) }

                Divider().padding(.vertical, 2)

                Text("LOAN").font(.footnote).foregroundColor(.secondary)

                row("phase", snapshot.map { String(describing: $0.phase) } ?? "—")
                row("epoch", snapshot?.epoch.map(String.init) ?? "—")
                row("mode", snapshot.map { $0.mode.rawValue } ?? "—")
                row("pump", (snapshot?.hasPumpManager ?? false) ? "constructed" : "nil")
                row("odometer", snapshot?.deliveredUnits.map { String(format: "%.2f U", $0) } ?? "—")
                row("loop IOB", iobText)
                row("fault", snapshot?.podFault ?? "none")
                row("last seq", snapshot.map { String($0.lastEventSeq) } ?? "—")
                row("unacked", snapshot.map { String($0.unackedCount) } ?? "—")
                row("last act", lastAction)

                Divider().padding(.vertical, 2)

                Text("POD LOAN").font(.footnote).foregroundColor(.secondary)

                Button("Keep a workout session running during loans: \(loanWorkout ? "ON" : "OFF") → tap to flip") {
                    loanWorkout.toggle()
                    SportLog.event("lab", "loan workout session = \(loanWorkout ? "ON — the soak holder spans the next loan" : "OFF — the app sleeps between bursts; takeover/hand-back keep their runtime")")
                    lastAction = "loan workout → \(loanWorkout ? "ON" : "OFF") — next loan"
                }

                Button("Read Pod Status") {
                    lastAction = "reading…"
                    session?.loanController.debugReadStatus { ok in
                        DispatchQueue.main.async {
                            switch ok {
                            case .some(true): lastAction = "pod status OK"
                            case .some(false): lastAction = "pod UNREACHABLE"
                            case .none: lastAction = "no pod (not in a loan)"
                            }
                        }
                    }
                }

                Divider().padding(.vertical, 2)

                Text("CGM HEALTH").font(.footnote).foregroundColor(.secondary)
                row("sensor", cgm?.sensorName ?? "none")
                row("last reading", cgm?.lastReadingAge.map { String(format: "%.0fs ago", $0) } ?? "never")
                row("bg", cgm?.bgLine ?? "—")
                row("link", cgm?.linkState ?? "—")
                row("state", cgm?.lifecycle ?? "—")
                row("expires", cgm?.expiresIn ?? "—")

                Text("SENSOR").font(.footnote).foregroundColor(.secondary)

                if let needs = G7WatchDirectRead.needsCodeFor {
                    Text("Sensor code needed for \(needs) — enter it in Loop ▸ Dexcom G7 on the phone (shown in the Dexcom app).")
                        .font(.caption2).foregroundColor(.red)
                }

                Picker("Re-lodge", selection: $relodge) {
                    Text("Pete's start delay").tag("peteDelay")
                    Text("Hold the app 35 s").tag("holdApp")
                }
                .pickerStyle(.navigationLink)
                .font(.caption2)
                .onChange(of: relodge) { _, arm in
                    SportLog.event("lab", "re-lodge = \(arm) — takes effect at the next close")
                    lastAction = "re-lodge → \(arm) — next close"
                }
                Text(relodge == "peteDelay"
                     ? "Pete's start delay, aimed at the next reading (≈298 s) — measured 1 in 4"
                     : "Hold the app 35 s after link-up, then a plain connect — measured 33 in 33; 35 s of runtime per cycle")
                    .font(.caption2).foregroundColor(.secondary)

                Button("Reconnect sensor") {
                    SportLog.event("g7-ble", "*** USER RECONNECT *** dropping the G7 link and re-acquiring the same sensor")
                    ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.stack.cgmManager.reconnectG7()
                    lastAction = "sensor reconnect started"
                }

                Divider().padding(.vertical, 2)

                NavigationLink("Logs") { LogView() }
                    .font(.caption)

                // Gated on GLANCE_DEMO rather than DEBUG: a Debug clone is built by people with
                // no way to know that a screenful of pod and insulin numbers is invented.
                #if GLANCE_DEMO
                NavigationLink("Glance demo") { GlanceDemoView() }
                    .font(.caption)
                #endif
            }
        }
        }
        .onReceive(refresh) { _ in
            tick()
        }
        .onAppear {
            tick()
        }
    }

    /// MAIN MUST NEVER SYNC ONTO THE LOOP OR LOAN QUEUES. The loan queue doubles as the pump's
    /// delegate queue, so a synchronous read here blocks main for the length of whatever pod
    /// operation is in flight — a bolus, a takeover, a reclaim — long enough for watchOS to kill
    /// the app. So each refresh ASKS the owner to republish its mirror and then reads the mirror
    /// that is already there; the value shown is the previous publish, which is the price.
    ///
    /// Keeping the previous value on a nil read (`?? snapshot`) matters too: a page that blanks
    /// whenever a publish is in flight reads as "the loan is gone".
    private func tick() {
        session?.loanController.refreshDebugSnapshot()
        snapshot = session?.loanController.mirroredDebugSnapshot ?? snapshot
        cgm = session.map { CGMHealth($0.stack.cgmManager) } ?? cgm

        RuntimeStateLog.mark("debug.tick")
        session?.stack.loopManager.refreshGlanceData()
        if let gd = session?.stack.loopManager.mirroredGlanceData {
            dosing = gd
            iobText = gd.iob.map { String(format: "%.2f U", $0) } ?? "—"
        }
        session?.stack.loopManager.glanceCarbsOnBoard { v in
            DispatchQueue.main.async { cobText = v.map { String(format: "%.0f g", $0) } ?? "—" }
        }
    }

    /// The eventual glucose broken into the effects that produced it, with `r` carrying whatever
    /// the named effects do not account for so the row adds up. `r` is NOT zero by construction —
    /// it is the quantity worth looking at when a prediction surprises you.
    @ViewBuilder
    private var predictionReconciliation: some View {
        if let b = dosing?.predictionBreakdown {
            let s = WatchLoopManager.PredictionBreakdown.round0(b.startMgdl)
            let ins = WatchLoopManager.PredictionBreakdown.round0(b.insulinMgdl)
            let carb = WatchLoopManager.PredictionBreakdown.round0(b.carbMgdl)
            let mom = WatchLoopManager.PredictionBreakdown.round0(b.momentumMgdl)
            let rc = WatchLoopManager.PredictionBreakdown.round0(b.retrospectiveMgdl)
            let ev = WatchLoopManager.PredictionBreakdown.round0(b.eventualMgdl)
            let r = WatchLoopManager.PredictionBreakdown.round0(ev - (s + ins + carb + mom + rc))
            Text(String(format: "%.0f ins%+.0f carb%+.0f mom%+.0f RC%+.0f r%+.0f = %.0f",
                        s, ins, carb, mom, rc, r, ev))
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "RC model: %@ · %d discrepanc%@",
                        (dosing?.retrospectiveCorrectionIsIntegral ?? false) ? "Integral" : "Standard",
                        dosing?.retrospectiveDiscrepancyCount ?? 0,
                        (dosing?.retrospectiveDiscrepancyCount ?? 0) == 1 ? "y" : "ies"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("— no prediction to reconcile")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption2)
        }
    }
}

/// The wrist's own log reader: tail it, share it, or send it to the phone. This is what makes a
/// field problem diagnosable without a Mac, on a build whose container no tool can reach.
struct LogView: View {
    @State private var text: String = ""
    @State private var sendNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if let url = LogFile.url {
                        // The phone files the transfer by this metadata "kind"; it is the same
                        // literal the session's automatic snapshots use.
                        WCSession.default.transferFile(url, metadata: ["kind": "g7watch.log"])
                        sendNote = "queued — appears in iPhone Files app (Loop folder)"
                    }
                } label: {
                    Label("Send Log to iPhone", systemImage: "iphone.and.arrow.forward")
                }
                .font(.caption)
                if let note = sendNote {
                    Text(note).font(.system(size: 10)).foregroundColor(.secondary)
                }

                ShareLink(item: text) {
                    Label("Share log", systemImage: "square.and.arrow.up")
                }
                .font(.caption)

                Button("Refresh") { load() }
                    .font(.caption)

                Text(text.isEmpty ? "no log yet" : text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Logs")
        .onAppear(perform: load)
    }

    /// Rendered NEWEST FIRST. The file is written oldest-first and there is no scroll position to
    /// restore on a watch, so the thing that just happened has to be at the top.
    private func load() {
        let tail = LogFile.tail()
        text = tail.split(separator: "\n", omittingEmptySubsequences: false)
            .reversed().joined(separator: "\n")
    }
}
