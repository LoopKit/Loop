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

final class WatchDataManager: NSObject {

    private unowned let deviceManager: DeviceDataManager
    
    init(deviceManager: DeviceDataManager, healthStore: HKHealthStore) {
        self.deviceManager = deviceManager
        self.sleepStore = SleepStore(healthStore: healthStore)
        self.lastBedtimeQuery = UserDefaults.appGroup?.lastBedtimeQuery ?? .distantPast
        self.bedtime = UserDefaults.appGroup?.bedtime

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(updateWatch(_:)), name: .LoopDataUpdated, object: deviceManager.loopManager)
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

    private var lastSentSettings: LoopSettings?
    private var lastSentBolusVolumes: [Double]?

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
            let rawUpdateContext = notification.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue,
            let updateContext = LoopDataManager.LoopUpdateContext(rawValue: rawUpdateContext)
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
        let settings = deviceManager.loopManager.settings

        guard let session = watchSession, session.isPaired, session.isWatchAppInstalled else {
            return
        }

        guard case .activated = session.activationState else {
            session.activate()
            return
        }

        guard settings != lastSentSettings else {
            log.default("Skipping settings transfer due to no changes")
            return
        }

        lastSentSettings = settings

        log.default("Transferring LoopSettingsUserInfo")
        session.transferUserInfo(LoopSettingsUserInfo(settings: settings).rawValue)
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
            log.default("Skipping bolus volumes transfer due to no changes")
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

        guard case .activated = session.activationState else {
            session.activate()
            return
        }

        createWatchContext { (context) in
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

    private func createWatchContext(recommendingBolusFor potentialCarbEntry: NewCarbEntry? = nil, _ completion: @escaping (_ context: WatchContext) -> Void) {
        let loopManager = deviceManager.loopManager!

        let glucose = deviceManager.glucoseStore.latestGlucose
        let reservoir =  deviceManager.doseStore.lastReservoirValue
        let basalDeliveryState = deviceManager.pumpManager?.status.basalDeliveryState

        loopManager.getLoopState { (manager, state) in
            let updateGroup = DispatchGroup()
            let context = WatchContext(glucose: glucose, glucoseUnit: self.deviceManager.glucoseStore.preferredUnit)
            context.reservoir = reservoir?.unitVolume
            context.loopLastRunDate = manager.lastLoopCompleted
            context.recommendedBolusDose = state.recommendedBolus?.recommendation.amount
            context.cob = state.carbsOnBoard?.quantity.doubleValue(for: HKUnit.gram())
            context.glucoseTrendRawValue = self.deviceManager.glucoseDisplay(for: glucose)?.trendType?.rawValue

            context.cgmManagerState = self.deviceManager.cgmManager?.rawValue

            if let trend = self.deviceManager.cgmManager?.glucoseDisplay?.trendType {
                context.glucoseTrendRawValue = trend.rawValue
            }
            
            if let potentialCarbEntry = potentialCarbEntry {
                context.potentialCarbEntry = potentialCarbEntry
                context.recommendedBolusDoseConsideringPotentialCarbEntry = try? state.recommendBolus(consideringPotentialCarbEntry: potentialCarbEntry, replacingCarbEntry: nil)?.amount
            }
            
            if let glucose = glucose {
                updateGroup.enter()
                self.deviceManager.glucoseStore.getCachedGlucoseSamples(start: glucose.startDate, end: nil) { (samples) in
                    if let sample = samples.last {
                        context.glucose = sample.quantity
                        context.glucoseDate = sample.startDate
                        context.glucoseIsDisplayOnly = sample.isDisplayOnly
                        context.glucoseWasUserEntered = sample.wasUserEntered
                        context.glucoseSyncIdentifier = sample.syncIdentifier
                    }
                    updateGroup.leave()
                }
            }

            updateGroup.enter()
            self.deviceManager.doseStore.insulinOnBoard(at: Date()) { (result) in
                switch result {
                case .success(let iobValue):
                    context.iob = iobValue.value
                case .failure:
                    context.iob = nil
                }
                updateGroup.leave()
            }

            if let basalDeliveryState = basalDeliveryState,
                let basalSchedule = manager.basalRateScheduleApplyingOverrideHistory,
                let netBasal = basalDeliveryState.getNetBasal(basalSchedule: basalSchedule, settings: manager.settings)
            {
                context.lastNetTempBasalDose = netBasal.rate
            }

            // Drop the first element in predictedGlucose because it is the current glucose
            if let predictedGlucose = state.predictedGlucoseIncludingPendingInsulin?.dropFirst(), predictedGlucose.count > 0 {
                context.predictedGlucose = WatchPredictedGlucose(values: Array(predictedGlucose))
            }

            _ = updateGroup.wait(timeout: .distantFuture)
            completion(context)
        }
    }

    private func addCarbEntryAndBolusFromWatchMessage(_ message: [String: Any]) {
        guard let bolus = SetBolusUserInfo(rawValue: message as SetBolusUserInfo.RawValue) else {
            log.error("Could not enact bolus from from unknown message: %{public}@", String(describing: message))
            return
        }

        func enactBolus() {
            guard bolus.value > 0 else {
                // Ensure active carbs is updated in the absence of a bolus
                sendWatchContextIfNeeded()
                return
            }

            deviceManager.enactBolus(units: bolus.value, at: bolus.startDate) { (error) in
                if error == nil {
                    self.deviceManager.analyticsServicesManager.didSetBolusFromWatch(bolus.value)
                }

                // When we've successfully started the bolus, send a new context with our new prediction
                self.sendWatchContextIfNeeded()
            }
        }

        if let carbEntry = bolus.carbEntry {
            deviceManager.loopManager.addCarbEntry(carbEntry) { (result) in
                switch result {
                case .success:
                    self.deviceManager.analyticsServicesManager.didAddCarbsFromWatch()
                    enactBolus()
                case .failure(let error):
                    self.log.error("%{public}@", String(describing: error))
                }
            }
        } else {
            enactBolus()
        }
    }
}


extension WatchDataManager: WCSessionDelegate {
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["name"] as? String {
        case PotentialCarbEntryUserInfo.name?:
            if let potentialCarbEntry = PotentialCarbEntryUserInfo(rawValue: message)?.carbEntry {
                self.createWatchContext(recommendingBolusFor: potentialCarbEntry) { (context) in
                    replyHandler(context.rawValue)
                }
            } else {
                log.error("Could not recommend bolus from from unknown message: %{public}@", String(describing: message))
                replyHandler([:])
            }
        case SetBolusUserInfo.name?:
            // Add carbs if applicable; start the bolus and reply when it's successfully requested
            addCarbEntryAndBolusFromWatchMessage(message)

            // Reply immediately
            replyHandler([:])
        case LoopSettingsUserInfo.name?:
            if let watchSettings = LoopSettingsUserInfo(rawValue: message)?.settings {
                // So far we only support watch changes of temporary schedule overrides
                var settings = deviceManager.loopManager.settings
                settings.preMealOverride = watchSettings.preMealOverride
                settings.scheduleOverride = watchSettings.scheduleOverride

                // Prevent re-sending these updated settings back to the watch
                lastSentSettings = settings
                deviceManager.loopManager.settings = settings
            }

            // Since target range affects recommended bolus, send back a new one
            createWatchContext { (context) in
                replyHandler(context.rawValue)
            }
        case CarbBackfillRequestUserInfo.name?:
            if let userInfo = CarbBackfillRequestUserInfo(rawValue: message) {
                deviceManager.carbStore.getSyncCarbObjects(start: userInfo.startDate) { (result) in
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
                deviceManager.glucoseStore.getCachedGlucoseSamples(start: userInfo.startDate.addingTimeInterval(1), end: nil) { (values) in
                    replyHandler(WatchHistoricalGlucose(with: values).rawValue)
                }
            } else {
                replyHandler([:])
            }
        case WatchContextRequestUserInfo.name?:
            self.createWatchContext { (context) in
                // Send back the updated prediction and recommended bolus
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
                lastSentSettings = nil
                sendSettingsIfNeeded()
                lastSentBolusVolumes = nil
                sendSupportedBolusVolumesIfNeeded()
            case LoopSettingsUserInfo.name:
                lastSentSettings = nil
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
        lastSentSettings = nil
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
            "lastSentSettings: \(String(describing: lastSentSettings))",
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
