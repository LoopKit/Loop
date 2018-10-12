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

final class WatchDataManager: NSObject {

    unowned let deviceManager: DeviceDataManager

    var settings: WatchSettings {
        didSet {
            UserDefaults.appGroup.watchSettings = settings
            AnalyticsManager.shared.didChangeWatchSettings(from: oldValue, to: settings)
        }
    }

    init(
        deviceManager: DeviceDataManager,
        settings: WatchSettings = UserDefaults.appGroup.watchSettings ?? .default
    ) {
        self.deviceManager = deviceManager
        self.settings = settings
        self.log = deviceManager.logger.forCategory("WatchDataManager")

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

    var isWatchAppAvailable: Bool {
        if let session = watchSession, session.isPaired && session.isWatchAppInstalled {
            return true
        } else {
            return false
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
            if let context = context {
                self.sendWatchContext(context)
            }
        }
    }

    private lazy var complicationUpdateManager = WatchComplicationUpdateManager(watchManager: self)

    private func sendWatchContext(_ context: WatchContext) {
        guard let session = watchSession, session.isPaired, session.isWatchAppInstalled else {
            return
        }

        guard case .activated = session.activationState else {
            session.activate()
            return
        }

        if session.isComplicationEnabled && complicationUpdateManager.shouldUpdateComplicationImmediately(with: context) {
            log.default("transferCurrentComplicationUserInfo")
            complicationUpdateManager.lastComplicationContext = context
            session.transferCurrentComplicationUserInfo(context.rawValue)
        } else {
            do {
                log.default("updateApplicationContext")
                try session.updateApplicationContext(context.rawValue)
            } catch let error {
                log.error(error)
            }
        }
    }

    private func createWatchContext(_ completion: @escaping (_ context: WatchContext?) -> Void) {
        let loopManager = deviceManager.loopManager!

        let glucose = loopManager.glucoseStore.latestGlucose
        let reservoir = loopManager.doseStore.lastReservoirValue

        loopManager.getLoopState { (manager, state) in
            let updateGroup = DispatchGroup()
            let context = WatchContext(glucose: glucose, glucoseUnit: manager.glucoseStore.preferredUnit)
            context.reservoir = reservoir?.unitVolume
            context.loopLastRunDate = manager.lastLoopCompleted
            context.recommendedBolusDose = state.recommendedBolus?.recommendation.amount
            context.cob = state.carbsOnBoard?.quantity.doubleValue(for: HKUnit.gram())
            context.glucoseTrendRawValue = self.deviceManager.cgmManager?.sensorState?.trendType?.rawValue

            context.cgmManagerState = self.deviceManager.cgmManager?.rawValue

            if let trend = self.deviceManager.cgmManager?.sensorState?.trendType {
                context.glucoseTrendRawValue = trend.rawValue
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

            // Only set this value in the Watch context if there is a temp basal running that hasn't ended yet
            let date = state.lastTempBasal?.startDate ?? Date()
            if let scheduledBasal = manager.basalRateSchedule?.between(start: date, end: date).first,
                let lastTempBasal = state.lastTempBasal,
                lastTempBasal.endDate > Date() {
                context.lastNetTempBasalDose =  lastTempBasal.unitsPerHour - scheduledBasal.value
            }

            // Drop the first element in predictedGlucose because it is the current glucose
            if let predictedGlucose = state.predictedGlucose?.dropFirst(), predictedGlucose.count > 0 {
                context.predictedGlucose = WatchPredictedGlucose(values: Array(predictedGlucose))
            }

            _ = updateGroup.wait(timeout: .distantFuture)
            completion(context)
        }
    }

    private func addCarbEntryFromWatchMessage(_ message: [String: Any], completionHandler: ((_ units: Double?) -> Void)? = nil) {
        if let carbEntry = CarbEntryUserInfo(rawValue: message) {
            let newEntry = NewCarbEntry(
                quantity: HKQuantity(unit: deviceManager.loopManager.carbStore.preferredUnit, doubleValue: carbEntry.value),
                startDate: carbEntry.startDate,
                foodType: nil,
                absorptionTime: carbEntry.absorptionTimeType.absorptionTimeFromDefaults(deviceManager.loopManager.carbStore.defaultAbsorptionTimes)
            )

            deviceManager.loopManager.addCarbEntryAndRecommendBolus(newEntry) { (result) in
                switch result {
                case .success(let recommendation):
                    AnalyticsManager.shared.didAddCarbsFromWatch(carbEntry.value)
                    completionHandler?(recommendation?.amount)
                case .failure(let error):
                    self.log.error(error)
                    completionHandler?(nil)
                }
            }
        } else {
            completionHandler?(nil)
        }
    }
}


extension WatchDataManager: WCSessionDelegate {
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["name"] as? String {
        case CarbEntryUserInfo.name?:
            addCarbEntryFromWatchMessage(message) { (units) in
                replyHandler(BolusSuggestionUserInfo(recommendedBolus: units ?? 0, maxBolus: self.deviceManager.loopManager.settings.maximumBolus).rawValue)
            }
        case SetBolusUserInfo.name?:
            if let bolus = SetBolusUserInfo(rawValue: message as SetBolusUserInfo.RawValue) {
                self.deviceManager.enactBolus(units: bolus.value, at: bolus.startDate) { (error) in
                    if error == nil {
                        AnalyticsManager.shared.didSetBolusFromWatch(bolus.value)
                    }
                }
            }

            replyHandler([:])
        case LoopSettingsUserInfo.name?:
            if let watchSettings = LoopSettingsUserInfo(rawValue: message)?.settings {
                // So far we only support watch changes of target range overrides
                var settings = deviceManager.loopManager.settings
                settings.glucoseTargetRangeSchedule = watchSettings.glucoseTargetRangeSchedule

                // Prevent re-sending these updated settings back to the watch
                lastSentSettings = settings
                deviceManager.loopManager.settings = settings
            }
            replyHandler([:])
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
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let name = userInfoTransfer.userInfo["name"] as? String
        if let error = error {
            log.error(error)

            // This might be useless, as userInfoTransfer.userInfo seems to be nil when error is non-nil.
            switch name {
            case LoopSettingsUserInfo.name, WatchContext.name:
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
            "lastSentSettings: \(String(describing: lastSentSettings))"
        ]

        if let session = watchSession {
            items.append(String(reflecting: session))
        } else {
            items.append(contentsOf: [
                "watchSession: nil"
            ])
        }

        items.append(String(reflecting: complicationUpdateManager))

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
}
