//
//  AlertManager.swift
//  Loop
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import UIKit
import Combine

protocol AlertManagerResponder: AnyObject {
    /// Method for our Handlers to call to kick off alert response.  Differs from AlertResponder because here we need the whole `Identifier`.
    func acknowledgeAlert(identifier: Alert.Identifier)
}

public enum AlertUserNotificationUserInfoKey: String {
    case alert, alertTimestamp
}

/// Main (singleton-ish) class that is responsible for:
/// - managing the different targets (handlers) that will post alerts
/// - managing the different responders that might acknowledge the alert
/// - serializing alerts to storage
/// - etc.
public final class AlertManager {
    private static let soundsDirectoryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).last!.appendingPathComponent("Sounds")

    private let log = DiagnosticLog(category: "AlertManager")

    static let managerIdentifier = "Loop"

    private var handlers: [AlertIssuer] = []
    private var responders: [String: Weak<AlertResponder>] = [:]
    private var soundVendors: [String: Weak<AlertSoundVendor>] = [:]

    // Defer issuance of new alerts until playback is done
    private var deferredAlerts: [Alert] = []
    private var playbackFinished: Bool

    private let fileManager: FileManager
    private let alertPresenter: AlertPresenter

    private var modalAlertIssuer: AlertIssuer!
    private var userNotificationAlertIssuer: AlertIssuer?

    let alertStore: AlertStore

    private let bluetoothPoweredOffIdentifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "bluetoothPoweredOff")

    lazy private var cancellables = Set<AnyCancellable>()

    // For testing
    var getCurrentDate = { return Date() }
    
    public init(alertPresenter: AlertPresenter,
                modalAlertIssuer: AlertIssuer? = nil,
                userNotificationAlertIssuer: AlertIssuer,
                fileManager: FileManager = FileManager.default,
                alertStore: AlertStore? = nil,
                expireAfter: TimeInterval = 24 /* hours */ * 60 /* minutes */ * 60 /* seconds */,
                bluetoothProvider: BluetoothProvider,
                preventIssuanceBeforePlayback: Bool = true
    ) {
        self.fileManager = fileManager
        playbackFinished = !preventIssuanceBeforePlayback
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let alertStoreDirectory = documentsDirectory?.appendingPathComponent("AlertStore")
        if let alertStoreDirectory = alertStoreDirectory {
            do {
                try fileManager.ensureDirectoryExists(at: alertStoreDirectory, with: FileProtectionType.completeUntilFirstUserAuthentication)
                log.debug("AlertStore directory ensured")
            } catch {
                log.error("Could not create AlertStore directory: %@", error.localizedDescription)
            }
        }
        self.alertStore = alertStore ?? AlertStore(storageDirectoryURL: alertStoreDirectory, expireAfter: expireAfter)
        self.alertPresenter = alertPresenter
        self.modalAlertIssuer = modalAlertIssuer ?? InAppModalAlertIssuer(alertPresenter: alertPresenter, alertManagerResponder: self)
        self.userNotificationAlertIssuer = userNotificationAlertIssuer
        handlers = [self.modalAlertIssuer, userNotificationAlertIssuer]

        bluetoothProvider.addBluetoothObserver(self, queue: .main)

        NotificationCenter.default.publisher(for: .LoopCompleted)
            .sink { [weak self] _ in
                self?.loopDidComplete()
            }
            .store(in: &cancellables)

    }

    public func addAlertResponder(managerIdentifier: String, alertResponder: AlertResponder) {
        responders[managerIdentifier] = Weak(alertResponder)
    }

    public func removeAlertResponder(managerIdentifier: String) {
        responders.removeValue(forKey: managerIdentifier)
    }

    public func addAlertSoundVendor(managerIdentifier: String, soundVendor: AlertSoundVendor) {
        soundVendors[managerIdentifier] = Weak(soundVendor)
        initializeSoundVendor(managerIdentifier, soundVendor)
    }

    public func removeAlertSoundVendor(managerIdentifier: String) {
        soundVendors.removeValue(forKey: managerIdentifier)
    }

    // MARK: - Bluetooth alerts

    private func onBluetoothPermissionDenied() {
        log.default("Bluetooth permission denied")
        let title = NSLocalizedString("Bluetooth Unavailable Alert", comment: "Bluetooth unavailable alert title")
        let body = NSLocalizedString("Loop has detected an issue with your Bluetooth settings, and will not work successfully until Bluetooth is enabled. You will not receive glucose readings, or be able to bolus.", comment: "Bluetooth unavailable alert body.")
        let content = Alert.Content(title: title,
                                      body: body,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        issueAlert(Alert(identifier: bluetoothPoweredOffIdentifier, foregroundContent: content, backgroundContent: content, trigger: .immediate))
    }

    private func onBluetoothPoweredOn() {
        log.default("Bluetooth powered on")
        retractAlert(identifier: bluetoothPoweredOffIdentifier)
    }

    private func onBluetoothPoweredOff() {
        log.default("Bluetooth powered off")
        let title = NSLocalizedString("Bluetooth Off Alert", comment: "Bluetooth off alert title")
        let bgBody = NSLocalizedString("Loop will not work successfully until Bluetooth is enabled. You will not receive glucose readings, or be able to bolus.", comment: "Bluetooth off background alert body.")
        let bgcontent = Alert.Content(title: title,
                                      body: bgBody,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        let fgBody = NSLocalizedString("Turn on Bluetooth to receive alerts, alarms or sensor glucose readings.", comment: "Bluetooth off foreground alert body")
        let fgcontent = Alert.Content(title: title,
                                      body: fgBody,
                                      acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        issueAlert(Alert(identifier: bluetoothPoweredOffIdentifier,
                                       foregroundContent: fgcontent,
                                       backgroundContent: bgcontent,
                                       trigger: .immediate,
                                       interruptionLevel: .critical))
    }

    // MARK: - Loop Not Running alerts

    func loopDidComplete() {
        clearLoopNotRunningNotifications()
        scheduleLoopNotRunningNotifications()
    }

    func scheduleLoopNotRunningNotifications() {
        // Give a little extra time for a loop-in-progress to complete
        let gracePeriod = TimeInterval(minutes: 0.5)

        var scheduledNotifications: [StoredLoopNotRunningNotification] = []

        for (minutes, isCritical) in [(20.0, false), (40.0, false), (60.0, true), (120.0, true)] {
            let notification = UNMutableNotificationContent()
            let failureInterval = TimeInterval(minutes: minutes)

            let formatter = DateComponentsFormatter()
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .full

            if let failureIntervalString = formatter.string(from: failureInterval)?.localizedLowercase {
                notification.body = String(format: NSLocalizedString("Loop has not completed successfully in %@", comment: "The notification alert describing a long-lasting loop failure. The substitution parameter is the time interval since the last loop"), failureIntervalString)
            }

            notification.title = NSLocalizedString("Loop Failure", comment: "The notification title for a loop failure")
            if isCritical, FeatureFlags.criticalAlertsEnabled {
                if #available(iOS 15.0, *) {
                    notification.interruptionLevel = .critical
                }
                notification.sound = .defaultCritical
            } else {
                if #available(iOS 15.0, *) {
                    notification.interruptionLevel = .timeSensitive
                }
                notification.sound = .default
            }
            notification.categoryIdentifier = LoopNotificationCategory.loopNotRunning.rawValue
            notification.threadIdentifier = LoopNotificationCategory.loopNotRunning.rawValue

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: failureInterval + gracePeriod,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "\(LoopNotificationCategory.loopNotRunning.rawValue)\(failureInterval)",
                content: notification,
                trigger: trigger
            )

            if let nextTriggerDate = trigger.nextTriggerDate() {
                let scheduledNotification = StoredLoopNotRunningNotification(
                    alertAt: nextTriggerDate,
                    title: notification.title,
                    body: notification.body,
                    timeInterval: failureInterval,
                    isCritical: isCritical)
                scheduledNotifications.append(scheduledNotification)
            }
            UNUserNotificationCenter.current().add(request)
        }
        UserDefaults.appGroup?.loopNotRunningNotifications = scheduledNotifications
    }

    func inferDeliveredLoopNotRunningNotifications() {
        // Infer that any past alerts have been delivered at this point
        let now = getCurrentDate()
        var stillPendingNotifications = [StoredLoopNotRunningNotification]()
        for notification in UserDefaults.appGroup?.loopNotRunningNotifications ?? [] {
            if notification.alertAt < now {
                let alertIdentifier = Alert.Identifier(managerIdentifier: "Loop", alertIdentifier: "loopNotLooping")
                let content = Alert.Content(title: notification.title, body: notification.body, acknowledgeActionButtonLabel: "ios-notification-default")
                let interruptionLevel: Alert.InterruptionLevel = notification.isCritical ? .critical : .timeSensitive
                let alert = Alert(identifier: alertIdentifier, foregroundContent: nil, backgroundContent: content, trigger: .immediate, interruptionLevel: interruptionLevel)
                recordIssued(alert: alert, at: notification.alertAt)
            } else {
                stillPendingNotifications.append(notification)
            }
        }
        UserDefaults.appGroup?.loopNotRunningNotifications = stillPendingNotifications
    }

    func clearLoopNotRunningNotifications() {
        inferDeliveredLoopNotRunningNotifications()

        // Clear out any existing not-running notifications
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let loopNotRunningIdentifiers = notifications.filter({
                $0.request.content.categoryIdentifier == LoopNotificationCategory.loopNotRunning.rawValue
            }).map({
                $0.request.identifier
            })

            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: loopNotRunningIdentifiers)
        }
    }

    // MARK: - Workout reminder
    private func scheduleWorkoutOverrideReminder() {
        issueAlert(workoutOverrideReminderAlert)
    }

    private func retractWorkoutOverrideReminder() {
        retractAlert(identifier: AlertManager.workoutOverrideReminderAlertIdentifier)
    }

    public static var workoutOverrideReminderAlertIdentifier: Alert.Identifier {
        return Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "WorkoutOverrideReminder")
    }

    public var workoutOverrideReminderAlert: Alert {
        let title = NSLocalizedString("Workout Temp Adjust Still On", comment: "Workout override still on reminder alert title")
        let body = NSLocalizedString("Workout Temp Adjust has been turned on for more than 24 hours. Make sure you still want it enabled, or turn it off in the app.", comment: "Workout override still on reminder alert body.")
        let content = Alert.Content(title: title,
                                    body: body,
                                    acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        return Alert(identifier: AlertManager.workoutOverrideReminderAlertIdentifier,
                     foregroundContent: content,
                     backgroundContent: content,
                     trigger: .delayed(interval: .hours(24)))
    }

}

// MARK: AlertManagerResponder implementation

extension AlertManager: AlertManagerResponder {
    func acknowledgeAlert(identifier: Alert.Identifier) {
        if let responder = responders[identifier.managerIdentifier]?.value {
            responder.acknowledgeAlert(alertIdentifier: identifier.alertIdentifier) { (error) in
                if let error = error {
                    self.presentAcknowledgementFailedAlert(error: error)
                }
            }
        }
        handlers.map { $0 as? AlertManagerResponder }.forEach { $0?.acknowledgeAlert(identifier: identifier) }
        alertStore.recordAcknowledgement(of: identifier)
    }
    
    func presentAcknowledgementFailedAlert(error: Error) {
        DispatchQueue.main.async {
            let message: String
            if let localizedError = error as? LocalizedError {
                message = [localizedError.localizedDescription, localizedError.recoverySuggestion].compactMap({$0}).joined(separator: "\n\n")
            } else {
                message = String(format: NSLocalizedString("%1$@ is unable to clear the alert from your device", comment: "Message for alert shown when alert acknowledgement fails for a device, and the device does not provide a LocalizedError. (1: app name)"), Bundle.main.bundleDisplayName)
            }
            self.log.info("Alert acknowledgement failed: %{public}@", message)

            let alert = UIAlertController(
                title: NSLocalizedString("Unable To Clear Alert", comment: "Title for alert shown when alert acknowledgement fails"),
                message: message,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action for alert when alert acknowledgment fails"), style: .default))
            
            self.alertPresenter.present(alert, animated: true)
        }
    }
}

// MARK: AlertIssuer implementation

extension AlertManager: AlertIssuer {

    public func issueAlert(_ alert: Alert) {
        guard playbackFinished else {
            deferredAlerts.append(alert)
            return
        }
        handlers.forEach { $0.issueAlert(alert) }
        alertStore.recordIssued(alert: alert)
    }

    public func retractAlert(identifier: Alert.Identifier) {
        handlers.forEach { $0.retractAlert(identifier: identifier) }
        alertStore.recordRetraction(of: identifier)
    }

    private func replayAlert(_ alert: Alert) {
        // Only alerts with foreground content are replayed
        if alert.foregroundContent != nil {
            modalAlertIssuer?.issueAlert(alert)
        }
    }
}

// MARK: Sound Support

extension AlertManager {

    public static func soundURL(for alert: Alert) -> URL? {
        guard let sound = alert.sound else { return nil }
        return soundURL(managerIdentifier: alert.identifier.managerIdentifier, sound: sound)
    }

    private static func soundURL(managerIdentifier: String, sound: Alert.Sound) -> URL? {
        guard let soundFileName = sound.filename else { return nil }

        // Seems all the sound files need to be in the sounds directory, so we namespace the filenames
        return soundsDirectoryURL.appendingPathComponent("\(managerIdentifier)-\(soundFileName)")
    }

    private func initializeSoundVendor(_ managerIdentifier: String, _ soundVendor: AlertSoundVendor) {
        let sounds = soundVendor.getSounds()
        guard let baseURL = soundVendor.getSoundBaseURL(), !sounds.isEmpty else {
            return
        }
        do {
            try fileManager.createDirectory(at: AlertManager.soundsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            for sound in sounds {
                if let fromFilename = sound.filename,
                    let toURL = AlertManager.soundURL(managerIdentifier: managerIdentifier, sound: sound) {
                    try fileManager.copyIfNewer(from: baseURL.appendingPathComponent(fromFilename), to: toURL)
                }
            }
        } catch {
            log.error("Unable to copy sound files from soundVendor %@: %@", managerIdentifier, String(describing: error))
        }
    }

}

// MARK: Alert Playback

extension AlertManager {

    func playbackAlertsFromPersistence() {
        playbackAlertsFromAlertStore()
    }

    private func playbackAlertsFromAlertStore() {
        let updateGroup = DispatchGroup()
        updateGroup.enter()
        alertStore.lookupAllUnacknowledgedUnretracted {
            switch $0 {
            case .failure(let error):
                self.log.error("Could not fetch unacknowledged alerts: %@", error.localizedDescription)
            case .success(let alerts):
                alerts.forEach { alert in
                    do {
                        self.replayAlert(try Alert(from: alert, adjustedForStorageTime: true))
                    } catch {
                        self.log.error("Error decoding alert from persistent storage: %@", error.localizedDescription)
                    }
                }
            }
            updateGroup.leave()
        }
        updateGroup.enter()
        alertStore.lookupAllAcknowledgedUnretractedRepeatingAlerts {
            switch $0 {
            case .failure(let error):
                self.log.error("Could not fetch acknowledged unretracted repeating alerts: %@", error.localizedDescription)
            case .success(let alerts):
                alerts.forEach { alert in
                    do {
                        self.replayAlert(try Alert(from: alert, adjustedForStorageTime: true))
                    } catch {
                        self.log.error("Error decoding alert from persistent storage: %@", error.localizedDescription)
                    }
                }
            }
            updateGroup.leave()
        }
        updateGroup.notify(queue: .main) {
            self.playbackFinished = true
            for alert in self.deferredAlerts {
                self.issueAlert(alert)
            }
        }
    }

}

// MARK: Alert storage access
extension AlertManager {

    func getStoredEntries(startDate: Date, completion: @escaping (_ report: String) -> Void) {
        alertStore.executeQuery(since: startDate, limit: 100) { result in
            switch result {
            case .failure(let error):
                completion("Error: \(error)")
            case .success(_, let objects):
                let encoder = JSONEncoder()
                let report = "## Alerts\n" + objects.map { object in
                    return """
                    **\(object.title ?? "??")**

                    * identifier: \(object.identifier.value)
                    * issued: \(object.issuedDate)
                    * acknowledged: \(object.acknowledgedDate?.description ?? "n/a")
                    * retracted: \(object.retractedDate?.description ?? "n/a")
                    * trigger: \(object.trigger)
                    * interruptionLevel: \(object.interruptionLevel)
                    * foregroundContent: \((try? encoder.encodeToStringIfPresent(object.foregroundContent)) ?? "n/a")
                    * backgroundContent: \((try? encoder.encodeToStringIfPresent(object.backgroundContent)) ?? "n/a")
                    * sound: \((try? encoder.encodeToStringIfPresent(object.sound)) ?? "n/a")
                    * metadata: \((try? encoder.encodeToStringIfPresent(object.metadata)) ?? "n/a")

                    """
                }.joined(separator: "\n")
                completion(report)
            }
        }
    }
}

// MARK: PersistedAlertStore
extension AlertManager: PersistedAlertStore {
    public func doesIssuedAlertExist(identifier: Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
        alertStore.lookupAllMatching(identifier: identifier) { result in
            switch result {
            case .success(let storedAlerts):
                completion(.success(!storedAlerts.isEmpty))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func lookupAllUnretracted(managerIdentifier: String, completion: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        alertStore.lookupAllUnretracted(managerIdentifier: managerIdentifier) {
            switch $0 {
            case .success(let alerts):
                do {
                    let result = try alerts.map {
                        PersistedAlert(
                            alert: try Alert(from: $0, adjustedForStorageTime: false),
                            issuedDate: $0.issuedDate,
                            retractedDate: $0.retractedDate,
                            acknowledgedDate: $0.acknowledgedDate
                        )
                    }
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func lookupAllUnacknowledgedUnretracted(managerIdentifier: String, completion: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        alertStore.lookupAllUnacknowledgedUnretracted(managerIdentifier: managerIdentifier) {
            switch $0 {
            case .success(let alerts):
                do {
                    let result = try alerts.map {
                        PersistedAlert(
                            alert: try Alert(from: $0, adjustedForStorageTime: false),
                            issuedDate: $0.issuedDate,
                            retractedDate: $0.retractedDate,
                            acknowledgedDate: $0.acknowledgedDate
                        )
                    }
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func recordRetractedAlert(_ alert: Alert, at date: Date) {
        alertStore.recordRetractedAlert(alert, at: date)
    }

    private func recordIssued(alert: Alert, at date: Date = Date(), completion: ((Result<Void, Error>) -> Void)? = nil) {
        alertStore.recordIssued(alert: alert, at: date, completion: completion)
    }
}

// MARK: Extensions

fileprivate extension SyncAlertObject {
    var title: String? {
        return foregroundContent?.title ?? backgroundContent?.title
    }
}

extension FileManager {
    
    func ensureDirectoryExists(at url: URL, with protectionType: FileProtectionType? = nil) throws {
        try createDirectory(at: url, withIntermediateDirectories: true, attributes: protectionType.map { [FileAttributeKey.protectionKey: $0 ] })
        guard let protectionType = protectionType else {
            return
        }
        // double check protection type
        var attrs = try attributesOfItem(atPath: url.path)
        if attrs[FileAttributeKey.protectionKey] as? FileProtectionType != protectionType {
            attrs[FileAttributeKey.protectionKey] = protectionType
            try setAttributes(attrs, ofItemAtPath: url.path)
        }
    }
 
    func copyIfNewer(from fromURL: URL, to toURL: URL) throws {
        if fileExists(atPath: toURL.path) {
            // If the source file is newer, remove the old one, otherwise skip it.
            let toCreationDate = try toURL.fileCreationDate(self)
            let fromCreationDate = try fromURL.fileCreationDate(self)
            if fromCreationDate > toCreationDate {
                try removeItem(at: toURL)
            } else {
                return
            }
        }
        try copyItem(at: fromURL, to: toURL)
    }
}

fileprivate extension URL {

    func fileCreationDate(_ fileManager: FileManager) throws -> Date {
        return try fileManager.attributesOfItem(atPath: self.path)[.creationDate] as! Date
    }
}


// MARK: - BluetoothObserver
extension AlertManager: BluetoothObserver {
    public func bluetoothDidUpdateState(_ state: BluetoothState) {
        switch state {
        case .poweredOn:
            onBluetoothPoweredOn()
        case .poweredOff:
            onBluetoothPoweredOff()
        case .unauthorized:
            onBluetoothPermissionDenied()
        default:
            return
        }
    }
}


// MARK: - PresetActivationObserver
extension AlertManager: PresetActivationObserver {
    func presetActivated(context: TemporaryScheduleOverride.Context, duration: TemporaryScheduleOverride.Duration) {
        switch context {
        case .legacyWorkout:
            if duration == .indefinite {
                scheduleWorkoutOverrideReminder()
            }
        default:
            break
        }
    }

    func presetDeactivated(context: TemporaryScheduleOverride.Context) {
        switch context {
        case .legacyWorkout:
            retractWorkoutOverrideReminder()
        default:
            break
        }
    }
}
