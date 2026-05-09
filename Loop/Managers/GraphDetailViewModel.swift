//
//  GraphDetailViewModel.swift
//  Loop
//
//  GraphDetailView — Data aggregation for a specific chart timestamp.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Combine
import Foundation
import HealthKit
import LoopKit

// MARK: - GraphDetailViewModel

final class GraphDetailViewModel: ObservableObject {
    @Published var data: GraphDetailData

    private let deviceManager: DeviceDataManager
    private var scrubThrottleTimer: Timer?
    private var lastReloadAt: Date = .distantPast
    /// Throttle window for scrub-driven reloads. 150ms gives ~6 updates/sec
    /// during continuous scrub — fast enough to feel live, slow enough to
    /// avoid flooding HealthKit/DoseStore with overlapping queries.
    private let scrubThrottleInterval: TimeInterval = 0.15

    init(date: Date, glucoseUnit: HKUnit, deviceManager: DeviceDataManager) {
        self.deviceManager = deviceManager
        self.data = GraphDetailData(date: date, glucoseUnit: glucoseUnit)
        loadData()
    }

    /// Update to a new date and reload all data.
    ///
    /// Uses a **leading-edge throttle**: the first scrub call (or any call
    /// after a quiet period ≥ `scrubThrottleInterval`) fires immediately so
    /// the popup updates live as the user drags. Subsequent calls inside
    /// the window are coalesced into a single trailing reload that fires
    /// once the throttle window closes — guarantees the popup always
    /// settles on the user's final position even if they stop mid-window.
    ///
    /// This replaces the previous pure-debounce behavior, which suppressed
    /// every reload until the user lifted their finger.
    func update(for date: Date) {
        // Update the date display immediately so the timestamp tracks the
        // user's finger even between data refreshes.
        data.date = date

        let now = Date()
        let elapsed = now.timeIntervalSince(lastReloadAt)

        if elapsed >= scrubThrottleInterval {
            // Leading edge — outside the throttle window, fire now.
            scrubThrottleTimer?.invalidate()
            scrubThrottleTimer = nil
            lastReloadAt = now
            reloadAtCurrentDate()
        } else {
            // Inside the window — coalesce into a trailing reload at the
            // window's end so the user lands on accurate data even if
            // they stop scrubbing right now.
            scrubThrottleTimer?.invalidate()
            let delay = scrubThrottleInterval - elapsed
            scrubThrottleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.lastReloadAt = Date()
                self.reloadAtCurrentDate()
            }
        }
    }

    /// Wipe stale values and re-fetch every series for `data.date`.
    /// Clearing is intentional — the load* methods only set a value when
    /// they find a sample near the new date, so without the wipe the
    /// previous date's values would linger when no nearby sample exists.
    private func reloadAtCurrentDate() {
        let currentDate = data.date
        data = GraphDetailData(date: currentDate, glucoseUnit: data.glucoseUnit)
        loadData()
    }

    // MARK: - Data Loading

    private func loadData() {
        loadGlucose()
        loadIOB()
        loadCOB()
        loadBolus()
        loadBasalRate()
        loadOverride()
        loadAutoPreset()
        loadHeartRate()
    }

    private func loadGlucose() {
        let window: TimeInterval = 5 * 60 // ±5 minutes
        let start = data.date.addingTimeInterval(-window)
        let end = data.date.addingTimeInterval(window)

        deviceManager.glucoseStore.getGlucoseSamples(start: start, end: end) { [weak self] result in
            guard let self = self, case .success(let samples) = result else { return }
            // Find closest sample to the target date
            let closest = samples.min(by: {
                abs($0.startDate.timeIntervalSince(self.data.date)) < abs($1.startDate.timeIntervalSince(self.data.date))
            })
            if let sample = closest {
                let value = sample.quantity.doubleValue(for: self.data.glucoseUnit)
                DispatchQueue.main.async {
                    self.data.glucoseValue = value
                }
            }
        }
    }

    private func loadIOB() {
        let start = data.date.addingTimeInterval(-5 * 60)
        let end = data.date.addingTimeInterval(5 * 60)

        deviceManager.doseStore.getInsulinOnBoardValues(start: start, end: end, basalDosingEnd: nil) { [weak self] result in
            guard let self = self, case .success(let values) = result else { return }
            let closest = values.min(by: {
                abs($0.startDate.timeIntervalSince(self.data.date)) < abs($1.startDate.timeIntervalSince(self.data.date))
            })
            if let iob = closest {
                DispatchQueue.main.async {
                    self.data.insulinOnBoard = iob.value
                }
            }
        }
    }

    private func loadCOB() {
        // COB requires counteraction effects from loop state, so we use a simpler approach
        // Query carb entries near this time to estimate
        deviceManager.loopManager.getLoopState { [weak self] (_, state) in
            guard let self = self else { return }
            if let cobValue = state.carbsOnBoard {
                // This is current COB — for historical, we approximate from the values array
                DispatchQueue.main.async {
                    // Only show if the date is recent (within last few minutes)
                    if abs(self.data.date.timeIntervalSinceNow) < 10 * 60 {
                        self.data.carbsOnBoard = cobValue.quantity.doubleValue(for: .gram())
                    }
                }
            }
        }
    }

    private func loadBolus() {
        // Find boluses within ±15 minutes of the target time
        let window: TimeInterval = 15 * 60
        let start = data.date.addingTimeInterval(-window)
        let end = data.date.addingTimeInterval(window)

        deviceManager.doseStore.getNormalizedDoseEntries(start: start, end: end) { [weak self] result in
            guard let self = self, case .success(let entries) = result else { return }
            // Find the closest bolus
            let boluses = entries.filter { $0.type == .bolus }
            let closest = boluses.min(by: {
                abs($0.startDate.timeIntervalSince(self.data.date)) < abs($1.startDate.timeIntervalSince(self.data.date))
            })
            if let bolus = closest, bolus.deliveredUnits ?? bolus.programmedUnits > 0 {
                DispatchQueue.main.async {
                    self.data.recentBolus = (
                        units: bolus.deliveredUnits ?? bolus.programmedUnits,
                        date: bolus.startDate
                    )
                }
            }
        }
    }

    private func loadBasalRate() {
        // Get the scheduled basal rate at this time
        if let schedule = deviceManager.loopManager.settings.basalRateSchedule {
            let rate = schedule.value(at: data.date)
            DispatchQueue.main.async {
                self.data.basalRate = rate
            }
        }
    }

    private func loadOverride() {
        // Check if an override was active at this time
        if let override = deviceManager.loopManager.settings.scheduleOverride,
           override.isActive(at: data.date) {
            let name: String
            switch override.context {
            case .preset(let preset):
                name = "\(preset.symbol) \(preset.name)"
            case .legacyWorkout:
                name = "🏃 Workout"
            case .preMeal:
                name = "🍽 Pre-Meal"
            case .custom:
                name = "⚙️ Custom Override"
            }
            DispatchQueue.main.async {
                self.data.activePreset = name
            }
        }
    }

    private func loadAutoPreset() {
        // Read AutoPresets activity log directly from UserDefaults (no compile-time dependency)
        guard let defaults = UserDefaults(suiteName: "com.loopkit.Loop.AutoPresets"),
              let settingsData = defaults.data(forKey: "settings") else { return }

        // Decode only the fields we need
        struct MinimalLogEntry: Decodable {
            let date: Date
            let event: String
            let presetName: String?
        }
        struct MinimalSettings: Decodable {
            let recentActivityLog: [MinimalLogEntry]?
        }

        guard let settings = try? JSONDecoder().decode(MinimalSettings.self, from: settingsData),
              let entries = settings.recentActivityLog else { return }

        var lastActivation: (name: String, date: Date)?
        var lastDeactivation: Date?

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard entry.date <= data.date else { break }
            if entry.event == "presetActivated" {
                lastActivation = (entry.presetName ?? "Active", entry.date)
            } else if entry.event == "presetDeactivated" {
                lastDeactivation = entry.date
            }
        }

        if let activation = lastActivation {
            let isStillActive = lastDeactivation == nil || lastDeactivation! < activation.date
            if isStillActive {
                DispatchQueue.main.async {
                    self.data.activeAutoPreset = activation.name
                }
            }
        }
    }

    private func loadHeartRate() {
        let healthStore = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let window: TimeInterval = 5 * 60
        let start = data.date.addingTimeInterval(-window)
        let end = data.date.addingTimeInterval(window)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 10,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample],
                  !samples.isEmpty else { return }

            // Find closest to target date
            let closest = samples.min(by: {
                abs($0.startDate.timeIntervalSince(self.data.date)) < abs($1.startDate.timeIntervalSince(self.data.date))
            })
            if let hr = closest {
                let bpm = hr.quantity.doubleValue(for: HKUnit(from: "count/min"))
                DispatchQueue.main.async {
                    self.data.heartRate = bpm
                }
            }
        }
        healthStore.execute(query)
    }
}
