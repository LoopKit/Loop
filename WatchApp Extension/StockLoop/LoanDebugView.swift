//
//  LoanDebugView.swift
//  WatchApp
//
//  The Sport Mode diagnostics page. It reads published mirrors only, never the loop or loan
//  queues.
//

import Foundation
import SwiftUI
import WatchKit
import WatchConnectivity
import HealthKit
import LoopKit
import G7SensorKit

/// The CGM's view of its sensor, taken whole at tick time from what the manager publishes.
struct CGMHealth {
    let sensorName: String?
    let lastReadingAge: TimeInterval?

    let bgLine: String
    let lifecycle: String
    let expiresIn: String
    let needsCodeFor: String?
    let isSearching: Bool

    init(_ manager: G7CGMManager) {
        sensorName = manager.sensorName
        needsCodeFor = manager.needsCodeForSensor
        isSearching = manager.isSearchingForSensor
        lastReadingAge = manager.latestReadingTimestamp.map { Date().timeIntervalSince($0) }
        if let g = manager.latestReading?.glucose, let t = manager.latestReadingTimestamp {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            bgLine = String(format: "%d mg/dL · %@ (%.0fs ago)", Int(g), f.string(from: t), Date().timeIntervalSince(t))
        } else {
            bgLine = "—"
        }
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

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// Always `sharedIfAvailable()`: under the SwiftUI lifecycle `WKApplication.shared().delegate`
    /// is nil.
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
                // The DOSING block is the automatic loop's last run, not the glance's display run.
                row("eventual", dosing?.dosingEventual.map { String(format: "%.0f", $0.doubleValue(for: .milligramsPerDeciliter)) } ?? "—")
                predictionReconciliation
                row("COB / IOB", "\(cobText) / \(iobText)")
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
                row("state", cgm?.lifecycle ?? "—")
                row("expires", cgm?.expiresIn ?? "—")

                if let needs = G7WatchDirectRead.needsCodeNote(for: cgm?.needsCodeFor) {
                    Text(needs).font(.caption2).foregroundColor(.red)
                }
                if let searching = G7WatchDirectRead.searchingNote(cgm?.isSearching ?? false) {
                    Text(searching).font(.caption2).foregroundColor(.orange)
                }

                Divider().padding(.vertical, 2)

                NavigationLink("Logs") { LogView() }
                    .font(.caption)
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

    /// Asks owners to republish, then reads the existing mirror; keeps the old value on nil.
    private func tick() {
        session?.loanController.refreshDebugSnapshot()
        snapshot = session?.loanController.mirroredDebugSnapshot ?? snapshot
        cgm = (session?.stack.loopManager.cgmManager as? G7CGMManager).map(CGMHealth.init) ?? cgm

        RuntimeStateLog.mark("debug.tick")
        session?.stack.loopManager.refreshGlanceData()
        if let gd = session?.stack.loopManager.mirroredGlanceData {
            dosing = gd
            iobText = gd.dosingIOB.map { String(format: "%.2f U", $0) } ?? "—"
            cobText = gd.dosingCOB.map { String(format: "%.0f g", $0) } ?? "—"
        }
    }

    /// Eventual glucose by effect; `r` is the unexplained remainder.
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

/// The wrist's log: tail, share, or send to the phone.
struct LogView: View {
    @State private var text: String = ""
    @State private var sendNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if let url = LogFile.url {
                        // The phone files the transfer by this kind.
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

    /// Newest first.
    private func load() {
        let tail = LogFile.tail()
        text = tail.split(separator: "\n", omittingEmptySubsequences: false)
            .reversed().joined(separator: "\n")
    }
}
