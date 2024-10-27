//
//  WatchDataManager.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import UIKit
import WatchConnectivity
import LoopKit
import LoopCore

@MainActor
final class WatchDataManager: NSObject {

    private unowned let deviceManager: DeviceDataManager
    private unowned let settingsManager: SettingsManager
    private unowned let loopDataManager: LoopDataManager
    private unowned let carbStore: CarbStore
    private unowned let glucoseStore: GlucoseStore
    private unowned let analyticsServicesManager: AnalyticsServicesManager?
    private unowned let temporaryPresetsManager: TemporaryPresetsManager

    init(
        deviceManager: DeviceDataManager,
        settingsManager: SettingsManager,
        loopDataManager: LoopDataManager,
        carbStore: CarbStore,
        glucoseStore: GlucoseStore,
        analyticsServicesManager: AnalyticsServicesManager?,
        temporaryPresetsManager: TemporaryPresetsManager,
        healthStore: HKHealthStore
    ) {
        self.deviceManager = deviceManager
        self.settingsManager = settingsManager
        self.loopDataManager = loopDataManager
        self.carbStore = carbStore
        self.glucoseStore = glucoseStore
        self.analyticsServicesManager = analyticsServicesManager
        self.temporaryPresetsManager = temporaryPresetsManager
        self.sleepStore = SleepStore(healthStore: healthStore)
        self.lastBedtimeQuery = UserDefaults.appGroup?.lastBedtimeQuery ?? .distantPast
        self.bedtime = UserDefaults.appGroup?.bedtime

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(updateWatch(_:)), name: .LoopDataUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sendSupportedBolusVolumesIfNeeded), name: .PumpManagerChanged, object: deviceManager)

        watchSession?.delegate = self
        watchSession?.activate()
    }

    private let log = DiagnosticLog(category: "WatchDataManager")

    private var watchSession: WCSession? = {
        if WCSession.isSupported() {
            return WCSession.default
        } else {
            return nil
        }
    }()

    private var lastSentUserInfo: LoopSettingsUserInfo?
    private var lastSentBolusVolumes: [Double]?

    private var contextDosingDecisions: [Date: BolusDosingDecision] {
        get { lockedContextDosingDecisions.value }
        set { lockedContextDosingDecisions.value = newValue }
    }
    private var lockedContextDosingDecisions: Locked<[Date: BolusDosingDecision]> = Locked([:])

    private let contextDosingDecisionExpirationDuration: TimeInterval = -.minutes(5)

    let sleepStore: SleepStore
    
    var lastBedtimeQuery: Date {
        didSet {
            UserDefaults.appGroup?.lastBedtimeQuery = lastBedtimeQuery
        }
    }
    
    var bedtime: Date? {
        didSet {
            UserDefaults.appGroup?.bedtime = bedtime
        }
    }
    
    private func updateBedtimeIfNeeded() {
        let now = Date()
        let lastUpdateInterval = now.timeIntervalSince(lastBedtimeQuery)
        
        guard lastUpdateInterval >= TimeInterval(hours: 24) else {
            // increment the bedtime by 1 day if it's before the current time, but we don't need to make another HealthKit query yet
            if let bedtime = bedtime, bedtime < now {
                let calendar = Calendar.current
                let hourComponent = calendar.component(.hour, from: bedtime)
                let minuteComponent = calendar.component(.minute, from: bedtime)
                
                if let newBedtime = calendar.nextDate(after: now, matching: DateComponents(hour: hourComponent, minute: minuteComponent), matchingPolicy: .nextTime) {
                    self.bedtime = newBedtime
                }
            }
            
            return
        }

        sleepStore.getAverageSleepStartTime() { (result) in

            self.lastBedtimeQuery = now
            
            switch result {
                case .success(let bedtime):
                    self.bedtime = bedtime
                case .failure:
                    self.bedtime = nil
            }
        }
    }

    @objc private func updateWatch(_ notification: Notification) {
        guard
            let rawUpdateContext = notification.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopUpdateContext.RawValue,
            let updateContext = LoopUpdateContext(rawValue: rawUpdateContext)
        else {
            return
        }

        // Any update context should trigger a watch update
        sendWatchContextIfNeeded()

        if case .preferences = updateContext {
            sendSettingsIfNeeded()
        }
    }

    private var lastComplicationContext: WatchContext?

    private let minTrendDrift: Double = 20
    private lazy var minTrendUnit = HKUnit.milligramsPerDeciliter

    private func sendSettingsIfNeeded() {
        let userInfo = LoopSettingsUserInfo(
            loopSettings: settingsManager.loopSettings,
            scheduleOverride: temporaryPresetsManager.scheduleOverride,
            preMealOverride: temporaryPresetsManager.preMealOverride)

        guard let session = watchSession, session.isPaired, session.isWatchAppInstalled else {
            return
        }

        guard case .activated = session.activationState else {
            session.activate()
            return
        }

        guard userInfo != lastSentUserInfo else {
            return
        }

        lastSentUserInfo = userInfo

        // clear any old pending settings transfers
        for transfer in session.outstandingUserInfoTransfers {
            if (transfer.userInfo["name"] as? String) == LoopSettingsUserInfo.name {
                log.default("Cancelling old setings transfer")
                transfer.cancel()
            }
        }

        let rawUserInfo = userInfo.rawValue
        log.default("Transferring LoopSettingsUserInfo: %{public}@", rawUserInfo)
        session.transferUserInfo(rawUserInfo)
    }

    @objc private func sendSupportedBolusVolumesIfNeeded() {
        guard
            let volumes = deviceManager.pumpManager?.supportedBolusVolumes,
            let session = watchSession,
            session.isPaired,
            session.isWatchAppInstalled
        else {
            return
        }

        guard case .activated = session.activationState else {
            session.activate()
            return
        }

        guard volumes != lastSentBolusVolumes else {
            return
        }

        lastSentBolusVolumes = volumes

        log.default("Transferring supported bolus volumes")
        session.transferUserInfo(SupportedBolusVolumesUserInfo(supportedBolusVolumes: volumes).rawValue)
    }

    private func sendWatchContextIfNeeded() {
        guard let session = watchSession, session.isPaired, session.isWatchAppInstalled else {
            return
        }

        log.default("*** sendWatchContextIfNeeded")

        guard case .activated = session.activationState else {
            session.activate()
            return
        }

        Task {
            let context = await createWatchContext()
            self.sendWatchContext(context)
        }
    }

    private func sendWatchContext(_ context: WatchContext) {
        guard let session = watchSession, session.isPaired, session.isWatchAppInstalled else {
            return
        }

        guard case .activated = session.activationState else {
            session.activate()
            return
        }

        let complicationShouldUpdate: Bool
        updateBedtimeIfNeeded()

        if let lastContext = lastComplicationContext,
            let lastGlucose = lastContext.glucose, let lastGlucoseDate = lastContext.glucoseDate,
            let newGlucose = context.glucose, let newGlucoseDate = context.glucoseDate
        {
            let enoughTimePassed = newGlucoseDate.timeIntervalSince(lastGlucoseDate) >= session.complicationUserInfoTransferInterval(bedtime: bedtime)
            let enoughTrendDrift = abs(newGlucose.doubleValue(for: minTrendUnit) - lastGlucose.doubleValue(for: minTrendUnit)) >= minTrendDrift

            complicationShouldUpdate = enoughTimePassed || enoughTrendDrift
        } else {
            complicationShouldUpdate = true
        }

        if session.isComplicationEnabled && complicationShouldUpdate {
            log.default("transferCurrentComplicationUserInfo")
            session.transferCurrentComplicationUserInfo(context.rawValue)
            lastComplicationContext = context
        } else {
            do {
                log.default("updateApplicationContext")
                try session.updateApplicationContext(context.rawValue)
            } catch let error {
                log.error("%{public}@", String(describing: error))
            }
        }
    }

    @MainActor
    private func createWatchContext(recommendingBolusFor potentialCarbEntry: NewCarbEntry? = nil) async -> WatchContext {
        var dosingDecision = BolusDosingDecision(for: .watchBolus)

        let glucose = loopDataManager.latestGlucose
        let reservoir = loopDataManager.lastReservoirValue
        let basalDeliveryState = deviceManager.pumpManager?.status.basalDeliveryState

        let (_, algoOutput) = loopDataManager.displayState.asTuple

        let carbsOnBoard = loopDataManager.activeCarbs

        let context = WatchContext(glucose: glucose, glucoseUnit: self.deviceManager.displayGlucosePreference.unit)
        context.reservoir = reservoir?.unitVolume
        context.loopLastRunDate = loopDataManager.lastLoopCompleted
        context.cob = carbsOnBoard?.quantity.doubleValue(for: HKUnit.gram())

        if let glucoseDisplay = self.deviceManager.glucoseDisplay(for: glucose) {
            context.glucoseTrend = glucoseDisplay.trendType
            context.glucoseTrendRate = glucoseDisplay.trendRate
        }

        dosingDecision.carbsOnBoard = carbsOnBoard

        context.cgmManagerState = self.deviceManager.cgmManager?.rawValue

        let settings = self.settingsManager.loopSettings

        context.isClosedLoop = settings.dosingEnabled

        context.potentialCarbEntry = potentialCarbEntry

        if let recommendedBolus = try? await loopDataManager.recommendManualBolus(
            manualGlucoseSample: nil,
            potentialCarbEntry: potentialCarbEntry,
            originalCarbEntry: nil
        ) {
            context.recommendedBolusDose = recommendedBolus.amount
            dosingDecision.manualBolusRecommendation = ManualBolusRecommendationWithDate(
                recommendation: recommendedBolus,
                date: Date())
        }

        var historicalGlucose: [HistoricalGlucoseValue]?

        if let glucose = glucose {
            var sample: StoredGlucoseSample?

            let historicalGlucoseStartDate = Date(timeIntervalSinceNow: -LoopCoreConstants.dosingDecisionHistoricalGlucoseInterval)
            if let input = loopDataManager.displayState.input {
                let start = min(historicalGlucoseStartDate, glucose.startDate)
                let samples = input.glucoseHistory.filterDateRange(start, nil)
                sample = samples.last
                historicalGlucose = samples.filter { $0.startDate >= historicalGlucoseStartDate }.map { HistoricalGlucoseValue(startDate: $0.startDate, quantity: $0.quantity) }
            }
            context.glucose = sample?.quantity
            context.glucoseDate = sample?.startDate
            context.glucoseIsDisplayOnly = sample?.isDisplayOnly
            context.glucoseWasUserEntered = sample?.wasUserEntered
            context.glucoseSyncIdentifier = sample?.syncIdentifier
        }

        context.iob = loopDataManager.activeInsulin?.value

        dosingDecision.historicalGlucose = historicalGlucose
        dosingDecision.insulinOnBoard = loopDataManager.activeInsulin

        if let basalDeliveryState = basalDeliveryState,
           let basalSchedule = self.temporaryPresetsManager.basalRateScheduleApplyingOverrideHistory,
           let netBasal = basalDeliveryState.getNetBasal(basalSchedule: basalSchedule, maximumBasalRatePerHour: self.settingsManager.settings.maximumBasalRatePerHour)
        {
            context.lastNetTempBasalDose = netBasal.rate
        }

        if let predictedGlucose = algoOutput?.predictedGlucose {
            // Drop the first element in predictedGlucose because it is the current glucose
            let filteredPredictedGlucose = predictedGlucose.dropFirst()
            if filteredPredictedGlucose.count > 0 {
                context.predictedGlucose = WatchPredictedGlucose(values: Array(filteredPredictedGlucose))
            }
        }

        dosingDecision.predictedGlucose = algoOutput?.predictedGlucose

        var preMealOverride = self.temporaryPresetsManager.preMealOverride
        if preMealOverride?.hasFinished() == true {
            preMealOverride = nil
        }

        var scheduleOverride = self.temporaryPresetsManager.scheduleOverride
        if scheduleOverride?.hasFinished() == true {
            scheduleOverride = nil
        }

        dosingDecision.scheduleOverride = scheduleOverride

        if scheduleOverride != nil || preMealOverride != nil {
            dosingDecision.glucoseTargetRangeSchedule = self.temporaryPresetsManager.effectiveGlucoseTargetRangeSchedule(presumingMealEntry: potentialCarbEntry != nil)
        } else {
            dosingDecision.glucoseTargetRangeSchedule = settings.glucoseTargetRangeSchedule
        }

        // Remove any expired context dosing decisions and add new
        self.contextDosingDecisions = self.contextDosingDecisions.filter { (date, _) in date.timeIntervalSinceNow > self.contextDosingDecisionExpirationDuration }
        self.contextDosingDecisions[context.creationDate] = dosingDecision

        return context
    }

    private func addCarbEntryAndBolusFromWatchMessage(_ message: [String: Any]) async throws {
        guard let bolus = SetBolusUserInfo(rawValue: message as SetBolusUserInfo.RawValue) else {
            log.error("Could not enact bolus from from unknown message: %{public}@", String(describing: message))
            return
        }

        // Prevent any delayed messages from enacting.
        guard bolus.startDate.timeIntervalSinceNow > -30 else {
            log.error("Could not enact expired bolus from watch: %{public}@", String(describing: message))
            return
        }

        var dosingDecision: BolusDosingDecision
        if let contextDate = bolus.contextDate, let contextDosingDecision = contextDosingDecisions[contextDate] {
            dosingDecision = contextDosingDecision
        } else {
            dosingDecision = BolusDosingDecision(for: .watchBolus)  // The user saved without waiting for recommendation (no bolus)
        }

        if let carbEntry = bolus.carbEntry {
            let storedCarbEntry = try await loopDataManager.addCarbEntry(carbEntry)
            dosingDecision.carbEntry = storedCarbEntry
            self.analyticsServicesManager?.didAddCarbs(source: "Watch", amount: storedCarbEntry.quantity.doubleValue(for: .gram()))
        } else {
            dosingDecision.carbEntry = nil
        }

        dosingDecision.manualBolusRequested = bolus.value
        await loopDataManager.storeManualBolusDosingDecision(dosingDecision, withDate: bolus.startDate)

        guard bolus.value > 0 else {
            // Ensure active carbs is updated in the absence of a bolus
            sendWatchContextIfNeeded()
            return
        }

        do {
            try await deviceManager.enactBolus(units: bolus.value, activationType: bolus.activationType)
            self.analyticsServicesManager?.didBolus(source: "Watch", units: bolus.value)
        } catch { }

        // When we've started the bolus, send a new context with our new prediction
        self.sendWatchContextIfNeeded()
    }
}


extension WatchDataManager: WCSessionDelegate {
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["name"] as? String {
        case PotentialCarbEntryUserInfo.name?:
            if let potentialCarbEntry = PotentialCarbEntryUserInfo(rawValue: message)?.carbEntry {
                Task { @MainActor in
                    let context = await createWatchContext(recommendingBolusFor: potentialCarbEntry)
                    replyHandler(context.rawValue)
                }
            } else {
                log.error("Could not recommend bolus from from unknown message: %{public}@", String(describing: message))
                replyHandler([:])
            }
        case SetBolusUserInfo.name?:
            // Add carbs if applicable; start the bolus and reply when it's successfully requested
            Task { @MainActor in
                try await addCarbEntryAndBolusFromWatchMessage(message)
            }
            // Reply immediately
            replyHandler([:])

        case LoopSettingsUserInfo.name?:
            if let userInfo = LoopSettingsUserInfo(rawValue: message) {
                // So far we only support watch changes of temporary schedule overrides
                temporaryPresetsManager.preMealOverride = userInfo.preMealOverride
                temporaryPresetsManager.scheduleOverride = userInfo.scheduleOverride

                // Prevent re-sending these updated settings back to the watch
                lastSentUserInfo?.preMealOverride = userInfo.preMealOverride
                lastSentUserInfo?.scheduleOverride = userInfo.scheduleOverride
            }

            // Since target range affects recommended bolus, send back a new one
            Task { @MainActor in
                let context = await createWatchContext()
                replyHandler(context.rawValue)
            }
        case CarbBackfillRequestUserInfo.name?:
            if let userInfo = CarbBackfillRequestUserInfo(rawValue: message) {
                carbStore.getSyncCarbObjects(start: userInfo.startDate) { (result) in
                    switch result {
                    case .failure(let error):
                        self.log.error("%{public}@", String(describing: error))
                        replyHandler([:])
                    case .success(let objects):
                        replyHandler(WatchHistoricalCarbs(objects: objects).rawValue)
                    }
                }
            } else {
                replyHandler([:])
            }
        case GlucoseBackfillRequestUserInfo.name?:
            if let userInfo = GlucoseBackfillRequestUserInfo(rawValue: message) {
                Task {
                    do {
                        let samples = try await glucoseStore.getSyncGlucoseSamples(start: userInfo.startDate.addingTimeInterval(1))
                        replyHandler(WatchHistoricalGlucose(samples: samples).rawValue)
                    } catch {
                        self.log.error("Failure getting sync glucose objects: %{public}@", String(describing: error))
                        replyHandler([:])
                    }
                }
            } else {
                replyHandler([:])
            }
        case WatchContextRequestUserInfo.name?:
            Task { @MainActor in
                let context = await createWatchContext()
                replyHandler(context.rawValue)
            }
        default:
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        assertionFailure("We currently don't expect any userInfo messages transferred from the watch side")
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        switch activationState {
        case .activated:
            if let error = error {
                log.error("%{public}@", String(describing: error))
            } else {
                sendSettingsIfNeeded()
                sendWatchContextIfNeeded()
                sendSupportedBolusVolumesIfNeeded()
            }
        case .inactive, .notActivated:
            break
        @unknown default:
            break
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            log.error("%{public}@", String(describing: error))

            // This might be useless, as userInfoTransfer.userInfo seems to be nil when error is non-nil.
            switch userInfoTransfer.userInfo["name"] as? String {
            case nil:
                lastSentUserInfo = nil
                sendSettingsIfNeeded()
                lastSentBolusVolumes = nil
                sendSupportedBolusVolumesIfNeeded()
            case LoopSettingsUserInfo.name:
                lastSentUserInfo = nil
                sendSettingsIfNeeded()
            case SupportedBolusVolumesUserInfo.name:
                lastSentBolusVolumes = nil
                sendSupportedBolusVolumesIfNeeded()
            default:
                break
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Nothing to do here
    }

    func sessionDidDeactivate(_ session: WCSession) {
        lastSentUserInfo = nil
        watchSession = WCSession.default
        watchSession?.delegate = self
        watchSession?.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        sendSettingsIfNeeded()
        sendSupportedBolusVolumesIfNeeded()
    }
}


extension WatchDataManager {
    override var debugDescription: String {
        var items = [
            "## WatchDataManager",
            "lastSentUserInfo: \(String(describing: lastSentUserInfo))",
            "lastComplicationContext: \(String(describing: lastComplicationContext))",
            "lastBedtimeQuery: \(String(describing: lastBedtimeQuery))",
            "bedtime: \(String(describing: bedtime))",
            "complicationUserInfoTransferInterval: \(round(watchSession?.complicationUserInfoTransferInterval(bedtime: bedtime).minutes ?? 0)) min"
        ]

        if let session = watchSession {
            items.append(String(reflecting: session))
        } else {
            items.append(contentsOf: [
                "watchSession: nil"
            ])
        }

        return items.joined(separator: "\n")
    }

}

extension WCSession {
    open override var debugDescription: String {
        return [
            "\(self)",
            "* hasContentPending: \(hasContentPending)",
            "* isComplicationEnabled: \(isComplicationEnabled)",
            "* isPaired: \(isPaired)",
            "* isReachable: \(isReachable)",
            "* isWatchAppInstalled: \(isWatchAppInstalled)",
            "* outstandingFileTransfers: \(outstandingFileTransfers)",
            "* outstandingUserInfoTransfers: \(outstandingUserInfoTransfers)",
            "* receivedApplicationContext: \(receivedApplicationContext)",
            "* remainingComplicationUserInfoTransfers: \(remainingComplicationUserInfoTransfers)",
            "* watchDirectoryURL: \(watchDirectoryURL?.absoluteString ?? "nil")",
        ].joined(separator: "\n")
    }
    
    fileprivate func complicationUserInfoTransferInterval(bedtime: Date?) -> TimeInterval {
        let now = Date()
        let timeUntilRefresh: TimeInterval

        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0), matchingPolicy: .nextTime) {
            // we can have a more frequent refresh rate if we only refresh when it's likely the user is awake (based on HealthKit sleep data)
            if let nextBedtime = bedtime {
                let timeUntilBedtime = nextBedtime.timeIntervalSince(now)
                // if bedtime is before the current time or more than 24 hours away, use midnight instead
                timeUntilRefresh = (0..<TimeInterval(hours: 24)).contains(timeUntilBedtime) ? timeUntilBedtime : midnight.timeIntervalSince(now)
            }
            // otherwise, since (in most cases) the complications allowance refreshes at midnight, base it on the time remaining until midnight
            else {
                timeUntilRefresh = midnight.timeIntervalSince(now)
            }
        } else {
            timeUntilRefresh = .hours(24)
        }
        
        return timeUntilRefresh / Double(remainingComplicationUserInfoTransfers + 1)
    }
}
