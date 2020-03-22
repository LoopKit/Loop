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

    unowned let deviceManager: DeviceDataManager

    init(deviceManager: DeviceDataManager) {
        self.deviceManager = deviceManager
        self.sleepStore = SleepStore (healthStore: deviceManager.loopManager.glucoseStore.healthStore)
        self.lastBedtimeQuery = UserDefaults.appGroup?.lastBedtimeQuery ?? .distantPast
        self.bedtime = UserDefaults.appGroup?.bedtime
        self.log = DiagnosticLogger.shared.forCategory("WatchDataManager")

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(updateWatch(_:)), name: .LoopDataUpdated, object: deviceManager.loopManager)

        watchSession?.delegate = self
        watchSession?.activate()
    }

    private let log: CategoryLogger

    private var watchSession: WCSession? = {
        if WCSession.isSupported() {
            return WCSession.default
        } else {
            return nil
        }
    }()

    private var lastSentSettings: LoopSettings?

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
        let calendar = Calendar.current
        
        guard lastUpdateInterval >= TimeInterval(hours: 24) else {
            // increment the bedtime by 1 day if it's before the current time, but we don't need to make another HealthKit query yet
            if let bedtime = bedtime, bedtime < now {
                let hourComponent = calendar.component(.hour, from: bedtime)
                let minuteComponent = calendar.component(.minute, from: bedtime)
                
                if let newBedtime = calendar.nextDate(after: now, matching: DateComponents(hour: hourComponent, minute: minuteComponent), matchingPolicy: .nextTime), newBedtime.timeIntervalSinceNow <= .hours(24) {
                    self.bedtime = newBedtime
                }
            }
            
            return
        }

        sleepStore.getAverageSleepStartTime() {
            (result) in

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

        switch updateContext {
        case .glucose, .tempBasal:
            sendWatchContextIfNeeded()
        case .preferences:
            sendSettingsIfNeeded()
        default:
            break
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
                log.error(error)
            }
        }
    }

    private func createWatchContext(_ completion: @escaping (_ context: WatchContext) -> Void) {
        let loopManager = deviceManager.loopManager!

        let glucose = loopManager.glucoseStore.latestGlucose
        let reservoir = loopManager.doseStore.lastReservoirValue
        let basalDeliveryState = deviceManager.pumpManager?.status.basalDeliveryState

        loopManager.getLoopState { (manager, state) in
            let updateGroup = DispatchGroup()
            let context = WatchContext(glucose: glucose, glucoseUnit: manager.glucoseStore.preferredUnit)
            context.reservoir = reservoir?.unitVolume
            context.loopLastRunDate = manager.lastLoopCompleted
            context.recommendedBolusDose = state.recommendedBolus?.recommendation.amount
            context.cob = state.carbsOnBoard?.quantity.doubleValue(for: HKUnit.gram())
            context.glucoseTrendRawValue = self.deviceManager.sensorState?.trendType?.rawValue

            context.cgmManagerState = self.deviceManager.cgmManager?.rawValue

            if let trend = self.deviceManager.cgmManager?.sensorState?.trendType {
                context.glucoseTrendRawValue = trend.rawValue
            }
            
            if let glucose = glucose {
                updateGroup.enter()
                manager.glucoseStore.getCachedGlucoseSamples(start: glucose.startDate) { (samples) in
                    if let sample = samples.last {
                        context.glucose = sample.quantity
                        context.glucoseDate = sample.startDate
                        context.glucoseSyncIdentifier = sample.syncIdentifier
                    }
                    updateGroup.leave()
                }
            }

            updateGroup.enter()
            manager.doseStore.insulinOnBoard(at: Date()) { (result) in
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

    private func addCarbEntryFromWatchMessage(_ message: [String: Any], completionHandler: ((_ error: Error?) -> Void)? = nil) {
        if let carbEntry = CarbEntryUserInfo(rawValue: message)?.carbEntry {
            deviceManager.loopManager.addCarbEntryAndRecommendBolus(carbEntry) { (result) in
                switch result {
                case .success:
                    AnalyticsManager.shared.didAddCarbsFromWatch()
                    completionHandler?(nil)
                case .failure(let error):
                    self.log.error(error)
                    completionHandler?(error)
                }
            }
        } else {
            log.error("Could not add carb entry from unknown message: \(message)")
            completionHandler?(nil)
        }
    }
}


extension WatchDataManager: WCSessionDelegate {
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["name"] as? String {
        case CarbEntryUserInfo.name?:
            addCarbEntryFromWatchMessage(message) { (_) in
                self.createWatchContext { (context) in
                    // Send back the updated prediction and recommended bolus
                    replyHandler(context.rawValue)
                }
            }
        case SetBolusUserInfo.name?:
            // Start the bolus and reply when it's successfully requested
            if let bolus = SetBolusUserInfo(rawValue: message as SetBolusUserInfo.RawValue) {
                self.deviceManager.enactBolus(units: bolus.value, at: bolus.startDate) { (error) in
                    if error == nil {
                        AnalyticsManager.shared.didSetBolusFromWatch(bolus.value)
                    }

                    // When we've successfully started the bolus, send a new context with our new prediction
                    self.sendWatchContextIfNeeded()
                }
            }

            // Reply immediately
            replyHandler([:])
        case LoopSettingsUserInfo.name?:
            if let watchSettings = LoopSettingsUserInfo(rawValue: message)?.settings {
                // So far we only support watch changes of temporary schedule overrides
                var settings = deviceManager.loopManager.settings
                settings.scheduleOverride = watchSettings.scheduleOverride

                // Prevent re-sending these updated settings back to the watch
                lastSentSettings = settings
                deviceManager.loopManager.settings = settings
            }

            // Since target range affects recommended bolus, send back a new one
            createWatchContext { (context) in
                replyHandler(context.rawValue)
            }
        case GlucoseBackfillRequestUserInfo.name?:
            if let userInfo = GlucoseBackfillRequestUserInfo(rawValue: message),
                let manager = deviceManager.loopManager {
                manager.glucoseStore.getCachedGlucoseSamples(start: userInfo.startDate.addingTimeInterval(1)) { (values) in
                    replyHandler(WatchHistoricalGlucose(with: values).rawValue)
                }
            } else {
                replyHandler([:])
            }
        default:
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        addCarbEntryFromWatchMessage(userInfo)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        switch activationState {
        case .activated:
            if let error = error {
                log.error(error)
            } else {
                sendSettingsIfNeeded()
                sendWatchContextIfNeeded()
            }
        case .inactive, .notActivated:
            break
        @unknown default:
            break
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            log.error(error)

            // This might be useless, as userInfoTransfer.userInfo seems to be nil when error is non-nil.
            switch userInfoTransfer.userInfo["name"] as? String {
            case LoopSettingsUserInfo.name?, .none:
                lastSentSettings = nil
                sendSettingsIfNeeded()
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
