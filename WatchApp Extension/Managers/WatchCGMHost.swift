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
import UserNotifications

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
    /// What the CGM still needs before the watch can read the sensor by itself; nil when nothing.
    private(set) var directReadNeed: CGMDirectReadNeed?

    private init() {
        if let raw = rawManager, let manager = watchCGMManager(rawValue: raw) {
            builtFrom = raw["builtFrom"] as? [String: Any]
            install(manager)
        }
    }

    private func updateStatusNote() {
        isReadingDirectly = cgmManager != nil
        sensorName = watchCGMSensorName(cgmManager)
        statusNote = watchCGMStatusNote(cgmManager)
        lastConnection = watchCGMLastConnection(cgmManager)
        let need = cgmManager?.directReadNeed
        if need != directReadNeed {
            let wasAwaitingPairing = directReadNeed == .pairingAcceptance
            directReadNeed = need
            if (need == .pairingAcceptance) != wasAwaitingPairing {
                SensorPairingNotice.update(needed: need == .pairingAcceptance)
            }
        }
    }

    /// The phone's context arrived. Builds a manager when its export names a different sensor or code,
    /// and lets go of the sensor when the phone stopped sharing.
    func update(from context: WatchContext) {
        guard let raw = context.cgmConfiguration, let configuration = SharedDeviceConfiguration(rawValue: raw) else {
            if cgmManager != nil {
                log.default("The phone stopped sharing its CGM; letting go of the sensor")
                remove()
            }
            return
        }
        if cgmManager != nil, let builtFrom, (builtFrom as NSDictionary).isEqual(to: configuration.state) {
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

    private func install(_ manager: CGMManager) {
        manager.cgmManagerDelegate = self
        manager.addStatusObserver(self, queue: .main)
        cgmManager = manager
        updateStatusNote()
    }

    private func remove() {
        guard let previous = cgmManager else { return }
        previous.cgmManagerDelegate = nil
        previous.removeStatusObserver(self)
        Task { await previous.delete() }
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
}

/// Its `cgmManager(_:didUpdate:)`, below, serves as delegate and as status observer: the search and the note
/// change without the manager's state changing, and reach only status observers.
extension WatchCGMHost: CGMManagerStatusObserver {}

extension WatchCGMHost: CGMManagerDelegate {
    func startDateToFilterNewData(for manager: CGMManager) async -> Date? {
        LoopDataManager.shared.glucoseStore?.latestGlucose?.startDate
    }

    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) async {
        switch readingResult {
        case .newData(let samples):
            log.default("Direct reading: %d sample(s)", samples.count)
            LoopDataManager.shared.addDirectGlucose(samples)
        case .error(let error):
            log.error("CGM reading error: %{public}@", String(describing: error))
        case .noData, .unreliableData:
            break
        }
    }

    nonisolated func cgmManager(_ manager: CGMManager, hasNew events: [PersistedCgmEvent]) async {}

    /// The phone owns the sensor; a manager passed its configuration lets go when the phone stops sharing.
    nonisolated func cgmManagerWantsDeletion(_ manager: CGMManager) async {}

    func cgmManagerDidUpdateState(_ manager: CGMManager) async {
        guard manager === cgmManager else { return }
        save(manager)
        updateStatusNote()
    }

    nonisolated func credentialStoragePrefix(for manager: CGMManager) -> String {
        "com.loopkit.Loop.WatchCGMHost"
    }

    nonisolated func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        Task { @MainActor in
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

/// Brings the person to the watch when the sensor asks to pair with it.
///
/// The watch always reads the sensor directly, with its own key and Bluetooth bond, whether the phone runs
/// alongside the Dexcom app or connects directly, so each new sensor asks the watch for its own pairing.
/// watchOS shows that pairing request only with Loop on screen. The CGM keeps the sensor's link meanwhile
/// and sends the request when Loop comes on screen, however it gets there; this notice is the usual way.
/// The sensor's connection is what gives the app the run time to post it: nothing is timed.
enum SensorPairingNotice {
    static let identifier = "com.loopkit.Loop.sensorPairingRequest"
    private static let log = OSLog(category: "SensorPairingNotice")

    @MainActor
    static func update(needed: Bool) {
        let center = UNUserNotificationCenter.current()
        guard needed else {
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            return
        }
        // With Loop on screen the system's request shows by itself.
        guard WKApplication.shared().applicationState != .active else {
            log.default("The sensor asks to pair with Loop on screen; no notice")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Sensor ready to pair", comment: "Watch notification title: a new sensor is waiting for its Bluetooth pairing request to be accepted on the watch")
        content.body = NSLocalizedString("Tap to open Loop, then tap Pair.", comment: "Watch notification body: how to accept a new sensor's Bluetooth pairing request")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error {
                log.error("The pairing notice could not be posted: %{public}@", error.localizedDescription)
            } else {
                log.default("The sensor asks to pair and Loop is not on screen; notice posted")
            }
        }
    }
}
