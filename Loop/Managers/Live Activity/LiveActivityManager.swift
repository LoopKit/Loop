//
//  LiveActivityManager.swift
//  Loop
//
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore
import UIKit

extension Notification.Name {
    static let LiveActivitySettingsChanged = Notification.Name(rawValue: "com.loopKit.notification.LiveActivitySettingsChanged")
}

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager: LiveActivityManagerProxy {
    private let glucoseStore: GlucoseStoreProtocol
    private let glucoseUnit: @MainActor () -> LoopUnit
    private let client: LiveActivityClient
    private let notificationCenter: NotificationCenter
    private let loadSettings: () -> LiveActivitySettings
    private let statusContext: () -> StatusExtensionContext?
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []

    private var scheduleOverride: TemporaryScheduleOverride?
    private var preMealOverride: TemporaryScheduleOverride?
    private var glucoseTargetRangeSchedule: GlucoseRangeSchedule?
    private var activeInsulin: InsulinValue?

    private var refreshTask: Task<Void, Never>?
    private var revision: UInt = 0
    private var needsInitialCleanup = true

    private let cobFormatter: NumberFormatter =  {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .none
        return numberFormatter
    }()
    private let iobFormatter: NumberFormatter =  {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .none
        numberFormatter.maximumFractionDigits = 1
        numberFormatter.minimumFractionDigits = 1
        return numberFormatter
    }()
    private let timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short
        
        return dateFormatter
    }()
    
    init?(
        glucoseStore: GlucoseStoreProtocol,
        glucoseUnit: @escaping @MainActor () -> LoopUnit,
        client: LiveActivityClient? = nil,
        notificationCenter: NotificationCenter = .default,
        settings: @escaping () -> LiveActivitySettings = { UserDefaults.standard.liveActivity ?? LiveActivitySettings() },
        statusContext: @escaping () -> StatusExtensionContext? = { UserDefaults.appGroup?.statusExtensionContext },
        now: @escaping () -> Date = Date.init
    ) {
        let client = client ?? ActivityKitLiveActivityClient()
        guard client.activitiesEnabled else { return nil }
        self.glucoseStore = glucoseStore
        self.glucoseUnit = glucoseUnit
        self.client = client
        self.notificationCenter = notificationCenter
        self.loadSettings = settings
        self.statusContext = statusContext
        self.now = now

        // Glucose must keep updating with no pump or suspended delivery, even when
        // dosing calculations and the last completed loop stop advancing.
        for (name, object) in [
            (GlucoseStore.glucoseSamplesDidChange, glucoseStore as AnyObject?),
            (.LiveActivitySettingsChanged, nil),
            (UIApplication.didBecomeActiveNotification, nil)
        ] {
            observers.append(notificationCenter.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestRefresh()
                }
            })
        }
        requestRefresh()
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        refreshTask?.cancel()
    }

    func update(
        scheduleOverride: TemporaryScheduleOverride?,
        preMealOverride: TemporaryScheduleOverride?,
        glucoseTargetRangeSchedule: GlucoseRangeSchedule?,
        activeInsulin: InsulinValue?
    ) {
        self.scheduleOverride = scheduleOverride
        self.preMealOverride = preMealOverride
        self.glucoseTargetRangeSchedule = glucoseTargetRangeSchedule
        self.activeInsulin = activeInsulin
        requestRefresh()
    }

    /// Request a refresh and wait until all requests received during it have been handled.
    func refresh() async {
        requestRefresh()
        await refreshTask?.value
    }

    private func requestRefresh() {
        revision &+= 1
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.drainRefreshes()
        }
    }

    private func drainRefreshes() async {
        defer { refreshTask = nil }
        while !Task.isCancelled {
            let requestedRevision = revision
            let settings = loadSettings()
            if !settings.enabled {
                await client.endActivities()
                needsInitialCleanup = false
            } else {
                do {
                    let date = now()
                    let history: TimeInterval = settings.addPredictiveLine ? .hours(2) : .hours(6)
                    // Suspend on the store; blocking an async executor here can deadlock Loop.
                    let samples = try await glucoseStore.getGlucoseSamples(
                        start: adjustedChartStart(date.addingTimeInterval(-history)),
                        end: date
                    )
                    guard !Task.isCancelled else { return }
                    // New input invalidates an in-flight fetch. Only the newest snapshot is published.
                    guard requestedRevision == revision else { continue }
                    let state = makeContentState(glucoseSamples: samples, unit: glucoseUnit(), settings: settings, now: date)
                    if needsInitialCleanup || (client.canCreateActivity && client.needsRecreation(settings: settings)) {
                        needsInitialCleanup = false
                        await client.endActivities()
                        guard !Task.isCancelled else { return }
                        guard requestedRevision == revision else { continue }
                    }
                    try await client.publish(state, settings: settings)
                } catch {
                    // Keep the last published snapshot if a store query or ActivityKit operation fails.
                    print("ERROR: Error refreshing live activity: \(error.localizedDescription)")
                }
            }
            if requestedRevision == revision { return }
        }
    }

    private func makeContentState(
        glucoseSamples: [StoredGlucoseSample],
        unit: LoopUnit,
        settings: LiveActivitySettings,
        now: Date
    ) -> GlucoseActivityAttributes.ContentState {
        let isMmol = unit == .millimolesPerLiter
        let statusContext = statusContext()
        let glucoseFormatter = NumberFormatter.glucoseFormatter(for: unit)

        let currentGlucose = glucoseSamples.last
        let current = currentGlucose?.quantity.doubleValue(for: unit)
        let trend = currentGlucose?.trend ?? (currentGlucose == nil ? nil : statusContext?.glucoseDisplay?.trendType)

        var delta = "??"
        if let current, glucoseSamples.count > 1 {
            let prevSample = glucoseSamples[glucoseSamples.count - 2]
            let deltaValue = current - prevSample.quantity.doubleValue(for: unit)
            delta = "\(deltaValue < 0 ? "-" : "+")\(glucoseFormatter.string(from: abs(deltaValue)) ?? "??")"
        }

        let bottomRow = self.getBottomRow(
            currentGlucose: current,
            trend: trend,
            settings: settings,
            now: now,
            delta: delta,
            statusContext: statusContext,
            glucoseFormatter: glucoseFormatter
        )
        var predicatedGlucose: [Double] = []
        if let samples = statusContext?.predictedGlucose?.values, settings.addPredictiveLine {
            predicatedGlucose = samples
        }

        let endDateChart: Date
        if !predicatedGlucose.isEmpty, let predicted = statusContext?.predictedGlucose {
            endDateChart = predicted.startDate.addingTimeInterval(.hours(4))
        } else {
            endDateChart = currentGlucose?.startDate ?? now
        }

        var presetContext: Preset? = nil
        if let override = self.preMealOverride ?? self.scheduleOverride, let start = glucoseSamples.first?.startDate {
            let presetStart = max(override.startDate, start)
            let presetEnd = override.duration.isInfinite ? endDateChart : min(override.actualEndDate, endDateChart)
            // Only create a preset if it overlaps the chart window. If the override ended
            // before the chart window starts (e.g. spacious mode only shows 2h of history),
            // presetEnd < presetStart and drawing a RectangleMark with those backwards dates
            // forces SwiftUI Charts to expand the x-axis far into the past.
            if presetStart <= presetEnd {
                let (title, iconSymbol) = override.liveActivityTitleAndSymbol()
                presetContext = Preset(
                    title: title,
                    iconSystemSymbolName: iconSymbol,
                    startDate: presetStart,
                    endDate: presetEnd,
                    minValue: override.settings.targetRange?.lowerBound.doubleValue(for: unit) ?? 0,
                    maxValue: override.settings.targetRange?.upperBound.doubleValue(for: unit) ?? 0
                )
            }
        }

        var glucoseRanges: [GlucoseRangeValue] = []
        if let glucoseRangeSchedule = self.glucoseTargetRangeSchedule, let start = glucoseSamples.first?.startDate {
            glucoseRanges = getGlucoseRanges(
                glucoseRangeSchedule: glucoseRangeSchedule,
                presetContext: presetContext,
                start: adjustedChartStart(start),
                end: adjustedChartEnd(endDateChart),
                unit: unit
            )
        }

        let chartSamples = Self.thinned(glucoseSamples)
        let yAxisPoints = chartSamples.map{ item in item.quantity.doubleValue(for: unit) } + predicatedGlucose
        let chartYAxis = ChartAxisGenerator.getYAxis(
            points: yAxisPoints,
            isMmol: unit == LoopUnit.millimolesPerLiter
        )

        return GlucoseActivityAttributes.ContentState(
            date: currentGlucose?.startDate ?? now,
            ended: false,
            preset: presetContext,
            glucoseRanges: glucoseRanges,
            currentGlucose: current,
            eventualGlucose: statusContext?.predictedGlucose?.values.last,
            trendType: trend,
            delta: delta,
            isMmol: isMmol,
            isCloseLoop: statusContext?.isClosedLoop ?? false,
            lastCompleted: statusContext?.lastLoopCompleted,
            bottomRow: bottomRow,
            // ActivityKit silently drops updates over 4 KB
            glucoseSamples: chartSamples.suffix(100).map { item in
                return GlucoseSampleAttributes(x: item.startDate, y: item.quantity.doubleValue(for: unit))
            },
            predicatedGlucose: predicatedGlucose,
            predicatedStartDate: statusContext?.predictedGlucose?.startDate,
            predicatedInterval: statusContext?.predictedGlucose?.interval,
            yAxisMarks: chartYAxis
        )

    }

    private func getInsulinOnBoard() -> String {
        guard let iob = activeInsulin?.value else { return "??" }
        return iobFormatter.string(from: iob) ?? "??"
    }
    
    /// At most one sample per ~5 minutes, keeping the latest, so one-minute CGMs fit the update size limit.
    static func thinned(_ samples: [StoredGlucoseSample], minimumSpacing: TimeInterval = .minutes(4.5)) -> [StoredGlucoseSample] {
        var kept: [StoredGlucoseSample] = []
        for sample in samples.reversed() {
            if let last = kept.last, last.startDate.timeIntervalSince(sample.startDate) < minimumSpacing {
                continue
            }
            kept.append(sample)
        }
        return kept.reversed()
    }

    // Pull the start back to HH:30 when needed to keep the nearest hour label visible.
    private func adjustedChartStart(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        guard minute > 30 else { return date }
        let startOfHour = calendar.dateInterval(of: .hour, for: date)!.start
        return startOfHour.addingTimeInterval(.minutes(30))
    }

    // If the chart end falls before the half-hour mark (HH:00–HH:29), push it forward to HH:30
    // so that the nearest hour label is never truncated at the right edge.
    private func adjustedChartEnd(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        guard minute < 30 else { return date }
        let startOfHour = calendar.dateInterval(of: .hour, for: date)!.start
        return startOfHour.addingTimeInterval(.minutes(30))
    }

    private func getGlucoseRanges(glucoseRangeSchedule: GlucoseRangeSchedule, presetContext: Preset?, start: Date, end: Date, unit: LoopUnit) -> [GlucoseRangeValue] {
        var glucoseRanges: [GlucoseRangeValue] = []
        for item in glucoseRangeSchedule.quantityBetween(start: start, end: end) {
            let minValue = item.value.lowerBound.doubleValue(for: unit)
            let maxValue = item.value.upperBound.doubleValue(for: unit)
            let startDate = max(item.startDate, start)
            let endDate = min(item.endDate, end)
            
            if let presetContext = presetContext {
                let noTargetRange = presetContext.minValue == 0 && presetContext.maxValue == 0
                if presetContext.startDate > startDate, presetContext.endDate < endDate {
                    // Override entirely within this schedule segment
                    glucoseRanges.append(GlucoseRangeValue(
                        id: UUID(),
                        minValue: minValue,
                        maxValue: maxValue,
                        startDate: startDate,
                        endDate: presetContext.startDate
                    ))
                    if noTargetRange {
                        glucoseRanges.append(GlucoseRangeValue(
                            id: UUID(),
                            minValue: minValue,
                            maxValue: maxValue,
                            startDate: presetContext.startDate,
                            endDate: presetContext.endDate,
                            isOverride: true
                        ))
                    }
                    glucoseRanges.append(GlucoseRangeValue(
                        id: UUID(),
                        minValue: minValue,
                        maxValue: maxValue,
                        startDate: presetContext.endDate,
                        endDate: endDate
                    ))
                } else if presetContext.endDate > startDate, presetContext.endDate < endDate {
                    // Override ends within this segment (started before)
                    if noTargetRange {
                        glucoseRanges.append(GlucoseRangeValue(
                            id: UUID(),
                            minValue: minValue,
                            maxValue: maxValue,
                            startDate: startDate,
                            endDate: presetContext.endDate,
                            isOverride: true
                        ))
                    }
                    glucoseRanges.append(GlucoseRangeValue(
                        id: UUID(),
                        minValue: minValue,
                        maxValue: maxValue,
                        startDate: presetContext.endDate,
                        endDate: endDate
                    ))
                } else if presetContext.startDate < endDate, presetContext.startDate > startDate {
                    // Override starts within this segment (ends after)
                    glucoseRanges.append(GlucoseRangeValue(
                        id: UUID(),
                        minValue: minValue,
                        maxValue: maxValue,
                        startDate: startDate,
                        endDate: presetContext.startDate
                    ))
                    if noTargetRange {
                        glucoseRanges.append(GlucoseRangeValue(
                            id: UUID(),
                            minValue: minValue,
                            maxValue: maxValue,
                            startDate: presetContext.startDate,
                            endDate: endDate,
                            isOverride: true
                        ))
                    }
                    if presetContext.endDate == end {
                        break
                    }
                } else if presetContext.startDate <= startDate, presetContext.endDate >= endDate {
                    // Override completely covers this segment
                    if noTargetRange {
                        glucoseRanges.append(GlucoseRangeValue(
                            id: UUID(),
                            minValue: minValue,
                            maxValue: maxValue,
                            startDate: startDate,
                            endDate: endDate,
                            isOverride: true
                        ))
                    }
                } else {
                    // No overlap with target and override
                    glucoseRanges.append(GlucoseRangeValue(
                        id: UUID(),
                        minValue: minValue,
                        maxValue: maxValue,
                        startDate: startDate,
                        endDate: endDate
                    ))
                }
            } else {
                glucoseRanges.append(GlucoseRangeValue(
                    id: UUID(),
                    minValue: minValue,
                    maxValue: maxValue,
                    startDate: startDate,
                    endDate: endDate
                ))
            }
        }
        
        return glucoseRanges
    }
    
    private func getBottomRow(currentGlucose: Double?, trend: GlucoseTrend?, settings: LiveActivitySettings, now: Date, delta: String, statusContext: StatusExtensionContext?, glucoseFormatter: NumberFormatter) -> [BottomRowItem] {
        return settings.bottomRowConfiguration.map { type in
            switch(type) {
            case .iob:
                return BottomRowItem.generic(label: type.name(), value: getInsulinOnBoard(), unit: "U")
                
            case .cob:
                var cob: String = "0"
                if let cobValue = statusContext?.carbsOnBoard {
                    cob = self.cobFormatter.string(from: cobValue) ?? "??"
                }
                return BottomRowItem.generic(label: type.name(), value: cob, unit: "g")
                
            case .basal:
                guard let netBasalContext = statusContext?.netBasal else {
                    return BottomRowItem.basal(rate: 0, percentage: 0)
                }

                return BottomRowItem.basal(rate: netBasalContext.rate, percentage: netBasalContext.percentage)
                
            case .currentBg:
                return BottomRowItem.currentBg(label: type.name(), value: currentGlucose.flatMap { glucoseFormatter.string(from: $0) } ?? "??", trend: trend)
                
            case .eventualBg:
                guard let eventual = statusContext?.predictedGlucose?.values.last else {
                    return BottomRowItem.generic(label: type.name(), value: "??", unit: "")
                }
                
                return BottomRowItem.generic(label: type.name(), value: glucoseFormatter.string(from: eventual) ?? "??", unit: "")
                
            case .deltaBg:
                return BottomRowItem.generic(label: type.name(), value: delta, unit: "")
                
            case .updatedAt:
                return BottomRowItem.generic(label: type.name(), value: timeFormatter.string(from: now), unit: "")
            }
       }
    }
    
}

extension TemporaryScheduleOverride {
    /// Returns the Live Activity preset display: a plain-text title (with emoji folded in)
    /// and, when the preset uses an SF Symbol, the symbol name to render via Image(systemName:).
    func liveActivityTitleAndSymbol() -> (title: String, systemSymbolName: String?) {
        switch context {
        case .preset(let preset):
            return Self.titleAndSymbol(for: preset)
        case .activity(let activity):
            return Self.titleAndSymbol(for: activity.preset)
        case .custom:
            return (NSLocalizedString("Custom preset", comment: "The title of the cell indicating a generic custom preset is enabled"), nil)
        case .preMeal:
            return (NSLocalizedString("Pre-meal Preset", comment: "Status row title for premeal override enabled"), "fork.knife")
        }
    }

    private static func titleAndSymbol(for preset: TemporaryPreset) -> (title: String, systemSymbolName: String?) {
        guard let symbol = preset.symbol else {
            return (preset.name, nil)
        }
        switch symbol.symbolType {
        case .emoji:
            return ("\(symbol.value) \(preset.name)", nil)
        case .systemImage:
            return (preset.name, symbol.value)
        case .image:
            // Asset-image symbols can't be loaded from the widget bundle; render name only.
            return (preset.name, nil)
        }
    }
}
