//
//  AlertManager.swift
//  Loop
//
//  Created by Rick Pasetto on 4/9/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol AlertManagerResponder: class {
    /// Method for our Handlers to call to kick off alert response.  Differs from AlertResponder because here we need the whole `Identifier`.
    func acknowledgeAlert(identifier: Alert.Identifier)
}

public protocol UserNotificationCenter {
    func add(_ request: UNNotificationRequest, withCompletionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers: [String])
    func removeDeliveredNotifications(withIdentifiers: [String])
    func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void)
    func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void)
}
extension UNUserNotificationCenter: UserNotificationCenter {}

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
    
    fileprivate static let timestampFormatter = ISO8601DateFormatter()
    
    private let log = DiagnosticLog(category: "AlertManager")

    private var handlers: [AlertPresenter] = []
    private var responders: [String: Weak<AlertResponder>] = [:]
    private var soundVendors: [String: Weak<AlertSoundVendor>] = [:]
    
    private let userNotificationCenter: UserNotificationCenter
    private let fileManager: FileManager
    
    private let alertStore: AlertStore

    public init(rootViewController: UIViewController,
                handlers: [AlertPresenter]? = nil,
                userNotificationCenter: UserNotificationCenter = UNUserNotificationCenter.current(),
                fileManager: FileManager = FileManager.default,
                alertStore: AlertStore? = nil) {
        self.userNotificationCenter = userNotificationCenter
        self.fileManager = fileManager
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        self.alertStore = alertStore ?? AlertStore(storageDirectoryURL: documentsDirectory)
        self.handlers = handlers ??
            [UserNotificationAlertPresenter(userNotificationCenter: userNotificationCenter),
            InAppModalAlertPresenter(rootViewController: rootViewController, alertManagerResponder: self)]
        
        playbackAlertsFromPersistence()
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
}

// MARK: AlertManagerResponder implementation

extension AlertManager: AlertManagerResponder {
    func acknowledgeAlert(identifier: Alert.Identifier) {
        if let responder = responders[identifier.managerIdentifier]?.value {
            responder.acknowledgeAlert(alertIdentifier: identifier.alertIdentifier)
        }
        // Also clear the alert from the NotificationCenter
        log.debug("Removing notification %@ from delivered & pending notifications", identifier.value)
        userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier.value])
        userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier.value])
        alertStore.recordAcknowledgement(of: identifier)
    }
}

// MARK: AlertPresenter implementation

extension AlertManager: AlertPresenter {

    public func issueAlert(_ alert: Alert) {
        handlers.forEach { $0.issueAlert(alert) }
        alertStore.recordIssued(alert: alert)
    }
    
    public func retractAlert(identifier: Alert.Identifier) {
        handlers.forEach { $0.retractAlert(identifier: identifier) }
        alertStore.recordRetraction(of: identifier)
    }
    
    private func replayAlert(_ alert: Alert) {
        handlers.forEach { $0.issueAlert(alert) }
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
    
    private func playbackAlertsFromPersistence() {
        playbackAlertsFromAlertStore()
    }
    
    private func playbackAlertsFromAlertStore() {
        alertStore.lookupAllUnacknowledged {
            switch $0 {
            case .failure(let error):
                self.log.error("Could not fetch unacknowledged alerts: %@", error.localizedDescription)
            case .success(let alerts):
                alerts.forEach { alert in
                    do {
                        self.replayAlert(try Alert(from: alert))
                    } catch {
                        self.log.error("Error decoding alert from persistent storage: %@", error.localizedDescription)
                    }
                }
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
            case .success(let entries):
                let report = "## Alerts\n" + entries.1.map { storedAlert in
                    return """
                    **\(storedAlert.title ?? "??")**
                    
                    * alertIdentifier: \(storedAlert.alertIdentifier)
                    * managerIdentifier: \(storedAlert.managerIdentifier)
                    * issued: \(storedAlert.issuedDate)
                    * acknowledged: \(storedAlert.acknowledgedDate?.description ?? "n/a")
                    * retracted: \(storedAlert.retractedDate?.description ?? "n/a")
                    * isCritical: \(storedAlert.isCritical)
                    * trigger: \(storedAlert.trigger)
                    * foregroundContent: \(storedAlert.foregroundContent ?? "n/a")
                    * backgroundContent: \(storedAlert.backgroundContent ?? "n/a")
                    * sound: \(storedAlert.sound ?? "n/a")

                    """
                }.joined(separator: "\n")
                completion(report)
            }
        }
    }
}

// MARK: Extensions

extension FileManager {
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

extension URL {
    
    func fileCreationDate(_ fileManager: FileManager) throws -> Date {
        return try fileManager.attributesOfItem(atPath: self.path)[.creationDate] as! Date
    }
}

public extension Alert {
    
    enum Error: String, Swift.Error {
        case noBackgroundContent
    }
        
    fileprivate func getUserNotificationContent(timestamp: Date) throws -> UNNotificationContent {
        guard let content = backgroundContent else {
            throw Error.noBackgroundContent
        }
        let userNotificationContent = UNMutableNotificationContent()
        userNotificationContent.title = content.title
        userNotificationContent.body = content.body
        userNotificationContent.sound = getUserNotificationSound()
        // TODO: Once we have a final design and approval for custom UserNotification buttons, we'll need to set categoryIdentifier
//        userNotificationContent.categoryIdentifier = LoopNotificationCategory.alert.rawValue
        userNotificationContent.threadIdentifier = identifier.value // Used to match categoryIdentifier, but I /think/ we want multiple threads for multiple alert types, no?
        userNotificationContent.userInfo = [
            LoopNotificationUserInfoKey.managerIDForAlert.rawValue: identifier.managerIdentifier,
            LoopNotificationUserInfoKey.alertTypeID.rawValue: identifier.alertIdentifier,
        ]
        let encodedAlert = try encodeToString()
        userNotificationContent.userInfo[AlertUserNotificationUserInfoKey.alert.rawValue] = encodedAlert
        userNotificationContent.userInfo[AlertUserNotificationUserInfoKey.alertTimestamp.rawValue] =
            AlertManager.timestampFormatter.string(from: timestamp)
        return userNotificationContent
    }
    
    private func getUserNotificationSound() -> UNNotificationSound? {
        guard let content = backgroundContent else {
            return nil
        }
        if let sound = sound {
            switch sound {
            case .vibrate:
                // TODO: Not sure how to "force" UNNotificationSound to "vibrate only"...so for now we just do the default
                break
            case .silence:
                // TODO: Not sure how to "force" UNNotificationSound to "silence"...so for now we just do the default
                break
            default:
                if let actualFileName = AlertManager.soundURL(for: self)?.lastPathComponent {
                    let unname = UNNotificationSoundName(rawValue: actualFileName)
                    return content.isCritical ? UNNotificationSound.criticalSoundNamed(unname) : UNNotificationSound(named: unname)
                }
            }
        }
        
        return content.isCritical ? .defaultCritical : .default
    }
}

public extension UNNotificationRequest {
    convenience init(from alert: Alert, timestamp: Date) throws {
        let uncontent = try alert.getUserNotificationContent(timestamp: timestamp)
        self.init(identifier: alert.identifier.value,
                  content: uncontent,
                  trigger: UNTimeIntervalNotificationTrigger(from: alert.trigger))
    }
}

fileprivate extension UNTimeIntervalNotificationTrigger {
    convenience init?(from alertTrigger: Alert.Trigger) {
        switch alertTrigger {
        case .immediate:
            return nil
        case .delayed(let timeInterval):
            self.init(timeInterval: timeInterval, repeats: false)
        case .repeating(let repeatInterval):
            self.init(timeInterval: repeatInterval, repeats: true)
        }
    }
}
