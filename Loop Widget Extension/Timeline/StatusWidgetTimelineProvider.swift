//
//  StatusWidgetTimelineProvider.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import OSLog
import WidgetKit

class StatusWidgetTimelineProvider: TimelineProvider {
    lazy var defaults = UserDefaults.appGroup
    
    lazy var healthStore = HKHealthStore()

    private let log = OSLog(category: "LoopWidgets")

    static let stalenessAge = TimeInterval(minutes: 6)

    lazy var cacheStore = PersistenceController.controllerInAppGroupDirectory()

    lazy var localCacheDuration = Bundle.main.localCacheDuration

    lazy var settingsStore: SettingsStore =  SettingsStore(
        store: cacheStore,
        expireAfter: localCacheDuration)

    lazy var glucoseStore = GlucoseStore(
        cacheStore: cacheStore,
        provenanceIdentifier: HKSource.default().bundleIdentifier
    )

    func placeholder(in context: Context) -> StatusWidgetTimelimeEntry {
        log.default("%{public}@: context=%{public}@", #function, String(describing: context))

        return StatusWidgetTimelimeEntry(date: Date(), contextUpdatedAt: Date(), lastLoopCompleted: nil, closeLoop: true, currentGlucose: nil, glucoseFetchedAt: Date(), delta: nil, unit: .milligramsPerDeciliter, sensor: nil, pumpHighlight: nil, netBasal: nil, eventualGlucose: nil, preMealPresetAllowed: true, preMealPresetActive: false, customPresetActive: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusWidgetTimelimeEntry) -> ()) {
        log.default("%{public}@: context=%{public}@", #function, String(describing: context))
        update { newEntry in
            completion(newEntry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusWidgetTimelimeEntry>) -> ()) {
        log.default("%{public}@: context=%{public}@", #function, String(describing: context))
        update { newEntry in
            var entries = [newEntry]
            var datesToRefreshWidget: [Date] = []

            // Dates Loop completion staleness changes
            if let lastLoopCompleted = newEntry.lastLoopCompleted {
                datesToRefreshWidget.append(lastLoopCompleted.addingTimeInterval(LoopCompletionFreshness.fresh.maxAge!+1)) // Turns yellow
                datesToRefreshWidget.append(lastLoopCompleted.addingTimeInterval(LoopCompletionFreshness.aging.maxAge!+1)) // Turns red
            }

            // Date glucose status staleness changes
            if let lastGlucoseFetch = newEntry.glucoseFetchedAt {
                let glucoseFetchStaleAt = lastGlucoseFetch.addingTimeInterval(StatusWidgetTimelineProvider.stalenessAge+1)
                datesToRefreshWidget.append(glucoseFetchStaleAt)
            }

            // Date glucose staleness changes
            if let lastBGTime = newEntry.currentGlucose?.startDate {
                let staleBgRefreshTime = lastBGTime.addingTimeInterval(LoopCoreConstants.inputDataRecencyInterval+1)
                datesToRefreshWidget.append(staleBgRefreshTime)
            }

            // Date context staleness changes
            datesToRefreshWidget.append(newEntry.contextUpdatedAt.addingTimeInterval(StatusWidgetTimelineProvider.stalenessAge+1))

            for date in datesToRefreshWidget {
                // Copy the previous entry but mark it as stale
                var copiedEntry = newEntry
                copiedEntry.date = date
                entries.append(copiedEntry)
            }
                                
            let nextHour = Date().addingTimeInterval(.hours(1))
            let timeline = Timeline(entries: entries, policy: .after(nextHour))
            self.log.default("Returning timeline: %{public}@", String(describing: datesToRefreshWidget))
            completion(timeline)
        }
    }
    
    func update(completion: @escaping (StatusWidgetTimelimeEntry) -> Void) {
        let group = DispatchGroup()

        var glucose: [StoredGlucoseSample] = []

        let startDate = Date(timeIntervalSinceNow: -LoopCoreConstants.inputDataRecencyInterval)

        group.enter()
        glucoseStore.getGlucoseSamples(start: startDate) { (result) in
            switch result {
            case .failure:
                self.log.error("Failed to fetch glucose after %{public}@", String(describing: startDate))
                glucose = []
            case .success(let samples):
                self.log.default("Fetched glucose: last = %{public}@, %{public}@", String(describing: samples.last?.startDate), String(describing: samples.last?.quantity))
                glucose = samples
            }
            group.leave()
        }
        group.wait()

        let finalGlucose = glucose

        Task { @MainActor in
            guard let defaults = self.defaults,
                  let context = defaults.statusExtensionContext,
                  let contextUpdatedAt = context.createdAt,
                  let unit = await healthStore.cachedPreferredUnits(for: .bloodGlucose)
            else {
                return
            }

            let lastCompleted = context.lastLoopCompleted

            let closeLoop = context.isClosedLoop ?? false
            
            let preMealPresetAllowed = context.preMealPresetAllowed ?? true
            let preMealPresetActive = context.preMealPresetActive ?? false
            let customPresetActive = context.customPresetActive ?? false

            let netBasal = context.netBasal

            let currentGlucose = finalGlucose.last
            var previousGlucose: GlucoseValue?

            if finalGlucose.count > 1 {
                previousGlucose = finalGlucose[finalGlucose.count - 2]
            }

            var delta: HKQuantity?

            // Making sure that previous glucose is within 6 mins of last glucose to avoid large deltas on sensor changes, missed readings, etc.
            if let prevGlucose = previousGlucose,
               let currGlucose = currentGlucose,
               currGlucose.startDate.timeIntervalSince(prevGlucose.startDate).minutes < 6
            {
                let deltaMGDL = currGlucose.quantity.doubleValue(for: .milligramsPerDeciliter) - prevGlucose.quantity.doubleValue(for: .milligramsPerDeciliter)
                delta = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: deltaMGDL)
            }

            let predictedGlucose = context.predictedGlucose?.samples

            let eventualGlucose = predictedGlucose?.last

            let updateDate = Date()

            let entry = StatusWidgetTimelimeEntry(
                date: updateDate,
                contextUpdatedAt: contextUpdatedAt,
                lastLoopCompleted: lastCompleted,
                closeLoop: closeLoop,
                currentGlucose: currentGlucose,
                glucoseFetchedAt: updateDate,
                delta: delta,
                unit: unit,
                sensor: context.glucoseDisplay,
                pumpHighlight: context.pumpStatusHighlightContext,
                netBasal: netBasal,
                eventualGlucose: eventualGlucose,
                preMealPresetAllowed: preMealPresetAllowed,
                preMealPresetActive: preMealPresetActive,
                customPresetActive: customPresetActive
            )

            self.log.default("StatusWidgetTimelimeEntry = %{public}@", String(describing: entry))
            self.log.default("pumpHighlight = %{public}@", String(describing: entry.pumpHighlight))

            completion(entry)
        }
    }
}
