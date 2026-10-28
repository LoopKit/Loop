//
//  WatchCGMHost.swift
//  WatchApp Extension
//
//  Reads the phone's CGM directly, when the phone's CGM manager shares its configuration: the
//  watch builds its own manager from that export, keeps it across launches and stores its
//  readings beside the phone's.
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore
import os.log
import WatchKit

@MainActor
@Observable
final class WatchCGMHost {
    static let shared = WatchCGMHost()

    @ObservationIgnored
    private let log = OSLog(category: "WatchCGMHost")

    /// The manager's `managerIdentifier`, `state`, and the export it was built from.
    @ObservationIgnored
    @PersistedProperty(key: "WatchCGMManager")
    private var rawManager: [String: Any]?

    @ObservationIgnored
    private(set) var cgmManager: CGMManager?
    @ObservationIgnored
    private var builtFrom: [String: Any]?

    /// For the sensor page.
    private(set) var isReadingDirectly = false
    private(set) var sensorName: String?
    private(set) var statusNote: String?
    private(set) var lastConnection: Date?

    /// A background refresh this long after each reading re-checks acquisition, in case watchOS froze
    /// the app before it lodged the next connect. Past the G7's 35 s tail clearance, so a connect it
    /// lodges never lands in the sensor's advertising tail.
    static let acquisitionBackstopDelay: TimeInterval = 60

    private init() {
        if let raw = rawManager, let manager = watchCGMManager(rawValue: raw) {
            builtFrom = raw["builtFrom"] as? [String: Any]
            install(manager)
        }
        NotificationCenter.default.addObserver(forName: watchCGMStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusNote() }
        }
    }

    private func updateStatusNote() {
        isReadingDirectly = cgmManager != nil
        sensorName = watchCGMSensorName(cgmManager)
        statusNote = watchCGMStatusNote(cgmManager)
        lastConnection = watchCGMLastConnection(cgmManager)
    }

    /// The phone's context arrived. Builds a manager when its export names a different sensor or code,
    /// lets go of the sensor when the phone stopped sharing, and otherwise treats it as a wake.
    func update(from context: WatchContext) {
        guard let raw = context.cgmConfiguration, let configuration = SharedDeviceConfiguration(rawValue: raw) else {
            if cgmManager != nil {
                log.default("The phone stopped sharing its CGM; letting go of the sensor")
                remove()
            }
            return
        }
        if cgmManager != nil, let builtFrom, (builtFrom as NSDictionary).isEqual(to: configuration.state) {
            recheckAcquisition()
            return
        }
        guard let manager = watchCGMManager(adopting: configuration, localState: nil) else {
            log.default("The phone's CGM (%{public}@) can't be read from the watch", configuration.managerIdentifier)
            return
        }
        log.default("CGM manager built from the phone's configuration (%{public}@)", configuration.managerIdentifier)
        remove()
        builtFrom = configuration.state
        install(manager)
        save(manager)
    }

    /// Any wake that is not the sensor's own.
    func recheckAcquisition() {
        watchCGMRecheckAcquisition(cgmManager)
    }

    private func install(_ manager: CGMManager) {
        manager.delegateQueue = .main
        manager.cgmManagerDelegate = self
        cgmManager = manager
        updateStatusNote()
    }

    private func remove() {
        guard let previous = cgmManager else { return }
        previous.cgmManagerDelegate = nil
        previous.delete {}
        cgmManager = nil
        builtFrom = nil
        rawManager = nil
        updateStatusNote()
        LoopDataManager.shared.directGlucoseDidEnd()
    }

    private func save(_ manager: CGMManager) {
        var raw = manager.watchRawValue
        raw["builtFrom"] = builtFrom
        rawManager = raw
    }

    private func scheduleAcquisitionBackstop() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date(timeIntervalSinceNow: Self.acquisitionBackstopDelay), userInfo: nil) { error in
            if let error {
                self.log.error("Could not schedule the acquisition backstop: %{public}@", String(describing: error))
            }
        }
    }
}

extension WatchCGMHost: CGMManagerDelegate {
    nonisolated func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        MainActor.assumeIsolated { LoopDataManager.shared.glucoseStore?.latestGlucose?.startDate }
    }

    nonisolated func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        MainActor.assumeIsolated {
            switch readingResult {
            case .newData(let samples):
                log.default("Direct reading: %d sample(s)", samples.count)
                LoopDataManager.shared.addDirectGlucose(samples)
                scheduleAcquisitionBackstop()
            case .error(let error):
                log.error("CGM reading error: %{public}@", String(describing: error))
            case .unreliableData:
                LoopDataManager.shared.directGlucoseUnreliable()
            case .noData:
                break
            }
        }
    }

    nonisolated func cgmManager(_ manager: CGMManager, hasNew events: [PersistedCgmEvent]) {}

    /// The phone owns the sensor; a manager passed its configuration lets go when the phone stops sharing.
    nonisolated func cgmManagerWantsDeletion(_ manager: CGMManager) async {}

    nonisolated func cgmManagerDidUpdateState(_ manager: CGMManager) {
        MainActor.assumeIsolated {
            guard manager === cgmManager else { return }
            save(manager)
            updateStatusNote()
        }
    }

    nonisolated func credentialStoragePrefix(for manager: CGMManager) -> String {
        "com.loopkit.Loop.WatchCGMHost"
    }

    nonisolated func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        MainActor.assumeIsolated {
            guard manager === cgmManager else { return }
            updateStatusNote()
        }
    }

    nonisolated func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        os_log("%{public}@ %{public}@", log: OSLog(category: "WatchCGMDevice"), type: .default, String(describing: type), message)
        completion?(nil)
    }

    nonisolated func deviceManager(_ manager: DeviceManager, recordAnalyticsEvent name: String, properties: [AnyHashable: Any]?) {}

    // The phone issues the sensor's alerts; the watch only logs them.
    nonisolated func issueAlert(_ alert: Alert) async {
        os_log("Alert from the watch's CGM, not shown: %{public}@", log: OSLog(category: "WatchCGMHost"), type: .default, alert.identifier.value)
    }

    nonisolated func retractAlert(identifier: Alert.Identifier) async {}

    nonisolated func doesIssuedAlertExist(identifier: Alert.Identifier) async throws -> Bool { false }

    nonisolated func lookupAllUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] { [] }

    nonisolated func lookupAllUnacknowledgedUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] { [] }

    nonisolated func recordRetractedAlert(_ alert: Alert, at date: Date) async throws {}
}
