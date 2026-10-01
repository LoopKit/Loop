//
//  PodLoanWatchController+SimulatorDriver.swift
//  StockLoop
//
//  Part of PodLoanWatchController (see PodLoanWatchController.swift). Split by concern; stored properties live in the core class.
//
//  A simulator-only stand-in for the loan protocol: it walks the phase machine on timers with no
//  phone, no grant, no journal and no pod, so the glance and the carb/bolus flow can be driven on
//  a Mac. Compiled out of every device build, and gated again at runtime by the `sim.fakeLoanFlow`
//  default so a simulator can still exercise the REAL protocol against a paired phone.
//

import Foundation
import HealthKit
import LoopKit
import LoopAlgorithm
import LoopCore
import OmnipodKit
import WatchKit
import os.log

extension PodLoanWatchController {
    #if targetEnvironment(simulator)

    /// Fakes idle → requested → takingOver → active on two timers. An epoch is bumped so the UI
    /// has one to render; no journal is begun and no pump manager is built, so nothing here can
    /// dose or be handed back for real.
    func simDriveStart() {
        queue.async {
            guard self.phase == .idle else { return }
            SportLog.event("sim", "SIM start — driving idle→active on timers (no pod/BLE)")
            self.lastIdleNote = nil
            self.attemptStartedAt = self.now()
            self.phase = .requested
            self.schedule(after: 0.8, label: "sim-grant") { [weak self] in
                guard let self, self.phase == .requested else { return }
                self.attemptStartedAt = self.now()
                self.phase = .takingOver
            }
            self.schedule(after: 2.4, label: "sim-active") { [weak self] in
                guard let self, self.phase == .takingOver else { return }
                self.epoch = (self.epoch ?? 0) + 1
                self.phase = .active
                self.loopManager.setClosedLoopEnabled(false)
                self.simStartGlucoseFeed()
            }
        }
    }

    /// The End counterpart. `beginHandback` refuses without a pump manager, so it routes here
    /// instead and drains to idle on a timer.
    func simDriveHandback() {
        queue.async {
            guard self.phase == .active else { return }
            SportLog.event("sim", "SIM hand-back — draining to idle")
            self.handbackRequested = true
            self.schedule(after: 2.5, label: "sim-handback") { [weak self] in
                guard let self, self.handbackRequested else { return }
                self.simStopGlucoseFeed()
                self.handbackRequested = false
                self.attemptStartedAt = nil
                self.phase = .idle
            }
        }
    }

    /// A synthetic reading every 30 s, so the glance and the loop have something to render.
    func simStartGlucoseFeed() {
        simStopGlucoseFeed()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 30)

        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.loopManager.simIngestPhoneGlucose() }
        }
        timer.resume()
        simGlucoseTimer = timer
    }

    private func simStopGlucoseFeed() {
        simGlucoseTimer?.cancel()
        simGlucoseTimer = nil
    }
    #endif
}
