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

class StatusWidgetProvider: TimelineProvider {
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

    func placeholder(in context: Context) -> StatusWidgetEntry {
        return StatusWidgetEntry(date: Date(), originalDate: Date(), lastLoopCompleted: nil, closeLoop: true, currentGlucose: nil, previousGlucose: nil, unit: .milligramsPerDeciliter, sensor: nil, netBasal: nil, eventualGlucose: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusWidgetEntry) -> ()) {
        update { newEntry in
            completion(newEntry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusWidgetEntry>) -> ()) {
        update { newEntry in
            var entries = [newEntry]
            var datesToRefreshWidget: [Date] = []
            let nextLoopRefresh = newEntry.lastLoopCompleted?.addingTimeInterval(.minutes(5)) ?? Date().addingTimeInterval(.minutes(5))

            if let lastBGTime = newEntry.currentGlucose?.startDate {
                let staleBgRefreshTime = lastBGTime.addingTimeInterval(.minutes(5))
                datesToRefreshWidget.append(staleBgRefreshTime)
            }

            datesToRefreshWidget.append(nextLoopRefresh)

            for date in datesToRefreshWidget {
                // Copy the previous entry but mark it as old but mark it as stale
                var copiedEntry = newEntry
                copiedEntry.date = date
                entries.append(copiedEntry)
            }
                                
            let nextHour = Date().addingTimeInterval(.hours(1))
            let timeline = Timeline(entries: entries, policy: .after(nextHour))
            completion(timeline)
        }
    }
    
    func update(completion: @escaping (StatusWidgetEntry) -> Void) {
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
            
            // Making sure that previous glucose is within 5 mins of last glucose to avoid large deltas on sensor changes, missed readings, etc.
            if let prevGlucose = previousGlucose,
               let currGlucose = currentGlucose,
               abs((prevGlucose.startDate.addingTimeInterval(.minutes(5)) - currGlucose.startDate).minutes) > 1 {
                previousGlucose = nil
            }

            let predictedGlucose = context.predictedGlucose?.samples
            
            let unit = context.predictedGlucose?.unit
            
            let eventualGlucose = predictedGlucose?.last
            
            completion(
                StatusWidgetEntry(
                    date: Date(),
                    originalDate: Date(),
                    lastLoopCompleted: lastCompleted,
                    closeLoop: closeLoop,
                    currentGlucose: currentGlucose,
                    previousGlucose: previousGlucose,
                    unit: unit,
                    sensor: context.glucoseDisplay,
                    netBasal: netBasal,
                    eventualGlucose: eventualGlucose
                )
            )
        }
    }
}


struct StatusWidgetEntry: TimelineEntry {
    var date: Date
    
    let originalDate: Date
    
    let lastLoopCompleted: Date?
    let closeLoop: Bool
    
    let currentGlucose: GlucoseValue?
    let previousGlucose: GlucoseValue?
    let unit: HKUnit?
    var sensor: GlucoseDisplayableContext?
    
    let netBasal: NetBasalContext?
    
    let eventualGlucose: GlucoseContext?
    
    // For marking old entries as stale
    var minsOld: Double {
        guard let lastLoopCompleted = lastLoopCompleted else {
            return 5
        }
        return (date - lastLoopCompleted).minutes
    }
    
    var isOld: Bool {
        return minsOld >= 5
    }
    
    var glucoseMinsOld: Double {
        guard let glucoseDate = currentGlucose?.startDate else {
            return 5
        }
        return (date - glucoseDate).minutes
    }
    
    var glucoseIsStale: Bool {
        return glucoseMinsOld >= 5
    }
}

extension Date {
    static func - (lhs: Date, rhs: Date) -> TimeInterval {
        return lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }
}

struct SmallStatusWidgetEntryView : View {
    var entry: StatusWidgetProvider.Entry

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
                        
            HStack(alignment: .center) {
                BasalView(entry: entry)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                if let eventualGlucose = entry.eventualGlucose {
                    let glucoseFormatter = NumberFormatter.glucoseFormatter(for: eventualGlucose.unit)
                    if let glucoseString = glucoseFormatter.string(from: eventualGlucose.quantity.doubleValue(for: eventualGlucose.unit)) {
                        VStack {
                            Text("FUTURE")
                            .font(.footnote)
                            .foregroundColor(entry.isOld ? Color(UIColor.systemGray3) : Color(UIColor.secondaryLabel))
                            
                            Text("\(glucoseString)")
                                .font(.subheadline)
                                .fontWeight(.heavy)
                            
                            Text(eventualGlucose.unit.shortLocalizedUnitString())
                                .font(.footnote)
                                .foregroundColor(entry.isOld ? Color(UIColor.systemGray3) : Color(UIColor.secondaryLabel))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(5)
            .background(
                ContainerRelativeShape()
                    .fill(Color("WidgetSecondaryBackground"))
            )
        }
        .foregroundColor(entry.isOld ? Color(UIColor.systemGray3) : nil)
        .padding(5)
        .background(Color("WidgetBackground"))
    }
}

@main
struct SmallStatusWidget: Widget {
    let kind: String = "SmallStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusWidgetProvider()) { entry in
            SmallStatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Loop Status Widget")
        .description("This widget displays your status.")
        .supportedFamilies([.systemSmall])
    }
}
