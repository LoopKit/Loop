//
//  SmallStatusWidget.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import WidgetKit
import SwiftUI
import LoopKit
import LoopCore
import HealthKit
import CoreData

class Provider: TimelineProvider {
    lazy var defaults = UserDefaults.appGroup
    
    lazy var healthStore = HKHealthStore()

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

    func placeholder(in context: Context) -> SmallStatusEntry {
        return SmallStatusEntry(date: Date(), lastLoopCompleted: nil, closeLoop: true, currentGlucose: nil, previousGlucose: nil, unit: .milligramsPerDeciliter, sensor: nil, netBasal: nil, eventualGlucose: nil, minsAgo: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (SmallStatusEntry) -> ()) {
        update { newEntry in
            completion(newEntry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        update { newEntry in
            var entries = [newEntry]
            
            let midnight = Calendar.current.startOfDay(for: Date())
            let nextHour = midnight.addingTimeInterval(.hours(1))
            
            for minute in 1..<60 {
                let entryDate = Date().addingTimeInterval(.minutes(Double(minute)))
                
                // Copy the previous entry but mark it as old and keep the old date so the user knows that the data is stale
                var oldEntry = newEntry
                oldEntry.date = entryDate
                oldEntry.minsAgo = minute
                entries.append(oldEntry)
            }
            
            
            let timeline = Timeline(entries: entries, policy: .after(nextHour))
            completion(timeline)
        }
    }
    
    func update(completion: @escaping (SmallStatusEntry) -> Void) {
        let group = DispatchGroup()

        var glucose: [StoredGlucoseSample] = []

        let startDate: Date = Calendar.current.nextDate(after: Date(timeIntervalSinceNow: .minutes(-5)), matching: DateComponents(minute: 0), matchingPolicy: .strict, direction: .backward) ?? Date()

        group.enter()
        glucoseStore.getGlucoseSamples(start: startDate) { (result) in
            switch result {
            case .failure:
                glucose = []
            case .success(let samples):
                glucose = samples
            }
            group.leave()
        }

        group.notify(queue: .main) {
            guard let defaults = self.defaults, let context = defaults.statusExtensionContext else {
                return
            }
            
            let lastCompleted = context.lastLoopCompleted
            
            let closeLoop = context.isClosedLoop ?? false
            
            let netBasal = context.netBasal
            
            var currentGlucose = glucose.last
            var previousGlucose: GlucoseValue?
            if glucose.count > 1 {
                previousGlucose = glucose[glucose.count - 2]
            }
            
            // Making sure that last glucose is not old
            if let currGlucose = currentGlucose, currGlucose.startDate.addingTimeInterval(LoopCoreConstants.inputDataRecencyInterval) < Date() {
                currentGlucose = nil
                previousGlucose = nil
            }
            
            // Making sure that previous glucose is within 15 mins of last glucose to avoid large deltas on sensor changes, missed readings, etc.
            if let prevGlucose = previousGlucose, prevGlucose.startDate.addingTimeInterval(.minutes(30)) < Date() {
                previousGlucose = nil
            }

            let predictedGlucose = context.predictedGlucose?.samples
            
            let unit = context.predictedGlucose?.unit
            
            let eventualGlucose = predictedGlucose?.last
            var eventualGlucoseString: String?
            if let unit = unit, let eventualGlucose = eventualGlucose {
                let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)
                eventualGlucoseString = glucoseFormatter.string(from: eventualGlucose.quantity.doubleValue(for: unit, withRounding: true))
            }
            
            completion(SmallStatusEntry(
                date: Date(),
                lastLoopCompleted: lastCompleted,
                closeLoop: closeLoop,
                currentGlucose: currentGlucose,
                previousGlucose: previousGlucose,
                unit: unit,
                sensor: context.glucoseDisplay,
                netBasal: netBasal,
                eventualGlucose: eventualGlucoseString,
                minsAgo: 0
            ))
        }
    }
}


struct SmallStatusEntry: TimelineEntry {
    var date: Date
    
    let lastLoopCompleted: Date?
    let closeLoop: Bool
    
    let currentGlucose: GlucoseValue?
    let previousGlucose: GlucoseValue?
    let unit: HKUnit?
    var sensor: GlucoseDisplayableContext?
    
    let netBasal: NetBasalContext?
    
    let eventualGlucose: String?
    
    // For marking old entries as stale
    var minsAgo: Int
}

struct SmallStatusWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(alignment: .center) {
                LoopCircleView(entry: entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // There is a SwiftUI bug which causes view not to be padded correctly when using .border
                // Added padding to counteract the width of the border
                    .padding(.leading, 8)
                
                GlucoseView(entry: entry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(5)
            .background(
                ContainerRelativeShape()
                    .fill(Color("WidgetSecondaryBackground"))
            )
            
            HStack(spacing: 2) {
                if entry.minsAgo >= 5 {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                
                Text("\(entry.minsAgo) min\(entry.minsAgo != 1 ? "s" : "") ago")
                    .font(.caption)
            }
            .foregroundColor(.primary)
            
            
            HStack(alignment: .center) {
                BasalView(entry: entry)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                VStack {
                    if let eventualGlucose = entry.eventualGlucose {
                        Text("Ev \(eventualGlucose)")
                            .font(.caption)
                    }
                    else {
                        Text("Ev --")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(5)
            .background(ContainerRelativeShape().fill(Color("WidgetSecondaryBackground")))
        }
        .foregroundColor(entry.minsAgo >= 5 ? Color(UIColor.systemGray3) : nil)
        .padding(5)
        .background(Color("WidgetBackground"))
    }
}

@main
struct SmallStatusWidget: Widget {
    let kind: String = "SmallStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SmallStatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Loop Status Widget")
        .description("This widget displays your status.")
        .supportedFamilies([.systemSmall])
    }
}
