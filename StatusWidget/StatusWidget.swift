//
//  SmallStatusWidget.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import os.log
import WidgetKit
import SwiftUI
import LoopKit
import LoopCore
import HealthKit

class StatusWidgetProvider: TimelineProvider {
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
        healthStore: healthStore,
        observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps,
        storeSamplesToHealthKit: false,
        cacheStore: cacheStore,
        observationEnabled: false,
        provenanceIdentifier: HKSource.default().bundleIdentifier
    )

    func placeholder(in context: Context) -> StatusWidgetEntry {
        log.default("%{public}@: context=%{public}@", #function, String(describing: context))

        return StatusWidgetEntry(date: Date(), contextUpdatedAt: Date(), lastLoopCompleted: nil, closeLoop: true, currentGlucose: nil, glucoseFetchedAt: Date(), delta: nil, unit: .milligramsPerDeciliter, sensor: nil, pumpHighlight: nil, netBasal: nil, eventualGlucose: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusWidgetEntry) -> ()) {
        log.default("%{public}@: context=%{public}@", #function, String(describing: context))
        update { newEntry in
            completion(newEntry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusWidgetEntry>) -> ()) {
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
                let glucoseFetchStaleAt = lastGlucoseFetch.addingTimeInterval(StatusWidgetProvider.stalenessAge+1)
                datesToRefreshWidget.append(glucoseFetchStaleAt)
            }

            // Date glucose staleness changes
            if let lastBGTime = newEntry.currentGlucose?.startDate {
                let staleBgRefreshTime = lastBGTime.addingTimeInterval(LoopCoreConstants.inputDataRecencyInterval+1)
                datesToRefreshWidget.append(staleBgRefreshTime)
            }

            // Date context staleness changes
            datesToRefreshWidget.append(newEntry.contextUpdatedAt.addingTimeInterval(StatusWidgetProvider.stalenessAge+1))

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
    
    func update(completion: @escaping (StatusWidgetEntry) -> Void) {
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
        group.notify(queue: .main) {
            guard let defaults = self.defaults,
                  let context = defaults.statusExtensionContext,
                  let contextUpdatedAt = context.createdAt,
                  let unit = self.glucoseStore.preferredUnit
            else {
                return
            }
            
            let lastCompleted = context.lastLoopCompleted
            
            let closeLoop = context.isClosedLoop ?? false
            
            let netBasal = context.netBasal
            
            let currentGlucose = glucose.last
            var previousGlucose: GlucoseValue?

            if glucose.count > 1 {
                previousGlucose = glucose[glucose.count - 2]
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

            let entry = StatusWidgetEntry(
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
                eventualGlucose: eventualGlucose
            )

            self.log.default("StatusWidgetEntry = %{public}@", String(describing: entry))
            self.log.default("pumpHighlight = %{public}@", String(describing: entry.pumpHighlight))

            completion(entry)
        }
    }
}


struct StatusWidgetEntry: TimelineEntry {
    var date: Date
    
    let contextUpdatedAt: Date
    
    let lastLoopCompleted: Date?
    let closeLoop: Bool
    
    let currentGlucose: GlucoseValue?
    let glucoseFetchedAt: Date?
    let delta: HKQuantity?
    let unit: HKUnit?
    let sensor: GlucoseDisplayableContext?

    let pumpHighlight: DeviceStatusHighlightContext?
    let netBasal: NetBasalContext?
    
    let eventualGlucose: GlucoseContext?
    
    // Whether context data is old
    var contextIsStale: Bool {
        return (date - contextUpdatedAt) >= StatusWidgetProvider.stalenessAge
    }

    var glucoseStatusIsStale: Bool {
        guard let glucoseFetchedAt = glucoseFetchedAt else {
            return true
        }
        let glucoseStatusAge = date - glucoseFetchedAt
        return glucoseStatusAge >= StatusWidgetProvider.stalenessAge
    }

    var glucoseIsStale: Bool {
        guard let glucoseDate = currentGlucose?.startDate else {
            return true
        }
        let glucoseAge = date - glucoseDate

        return glucoseAge >= LoopCoreConstants.inputDataRecencyInterval
    }
}

extension Date {
    static func - (lhs: Date, rhs: Date) -> TimeInterval {
        return lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }
}

struct SmallStatusWidget: Widget {
    let kind: String = "SmallStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusWidgetProvider()) { entry in
            SmallStatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Loop Status Widget")
        .description("See your current blood glucose and insulin delivery.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct SmallStatusWidgets: WidgetBundle {
    var body: some Widget {
        SmallStatusWidget()
   }
}
