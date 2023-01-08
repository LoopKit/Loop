//
//  RemoteCommandQueue.swift
//  Loop
//
//  Created by Bill Gestrich on 12/28/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import UIKit //For BackgroundTask

/*
 TODO:
 
 * Tracking of enacted commands by ID for safety (i.e. in CoreData)
 * Unit Tests
 
 */
actor RemoteCommandQueue {
    
    private let log = DiagnosticLog(category: "RemoteCommandQueue")
    
    private var commandSource: RemoteCommandSource?
    private weak var actionDelegate: RemoteCommandActionDelegate?
    
    enum RemoteCommandQueueError: LocalizedError {
        case missingActionDelegate
        case missingCommandSource
        case remoteCommandsDisabled
        case unexpectedDuplicateCommand
        case failedCommandIDPersistenceSave
        case failedCommandIDPersistenceFetch
        
        var errorDescription: String? {
            switch self {
            case .missingActionDelegate:
                return "Missing Action Delegate"
            case .missingCommandSource:
                return "Missing Command Source"
            case .remoteCommandsDisabled:
                return "Remote Commands Disabled"
            case .unexpectedDuplicateCommand:
                return "Duplicate Command"
            case .failedCommandIDPersistenceSave:
                return "Failed Command Save"
            case .failedCommandIDPersistenceFetch:
                return "Failed Saved Command Fetch"
            }
        }
    }
    
    func setCommandSource(_ commandSource: RemoteCommandSource) {
        self.commandSource = commandSource
    }
    
    func setActionDelegate(_ actionDelegate: RemoteCommandActionDelegate) {
        self.actionDelegate = actionDelegate
    }
    
    
    //MARK: Command Handling
    
    func handleCommand(_ command: RemoteCommand) async throws {
        do {
            try await handleCommand_notHandlingSuccessOrFailure(command)
            try await command.markSuccess()
        } catch {
            try await command.markError(error)
            throw error
        }
    }
    
    //TODO This one does not report the success or failure states.
    //Need to think how to restructure this.
    internal func handleCommand_notHandlingSuccessOrFailure(_ command: RemoteCommand) async throws {
        
        guard let actionDelegate = actionDelegate else {
            assertionFailure("Missing action delegate")
            throw RemoteCommandQueueError.missingActionDelegate
        }
        
        guard FeatureFlags.remoteOverridesEnabled else {
            //TODO: Users are being told to use this to disable remote bolus/carbs.
            //Consider if we should rename this to remoteCommandsEnabled
            log.error("Remote Notification: Remote commands not enabled.")
            throw RemoteCommandQueueError.remoteCommandsDisabled
        }
        
        guard try !commandWasPreviouslyQueued(command: command) else {
            throw RemoteCommandQueueError.unexpectedDuplicateCommand
        }
        
        try markCommandAsQueued(command: command)
        try command.checkValidity()
        try await command.markInProgress()
        try await actionDelegate.remoteCommandQueue(self, handleCommandAction: command.action)
    }
    
    func handlePendingRemoteCommands() async {
        let backgroundTask = await beginBackgroundTask(name: "Handle Pending Remote Commands")
        
        do {
            guard let commandSource = commandSource else {
                assertionFailure("Missing command source")
                throw RemoteCommandQueueError.missingCommandSource
            }
            for command in try await commandSource.fetchPendingRemoteCommands() {
                do { //Nested try/catch is so we can still continue processing commands when a single one fails.
                    switch command.action {
                    case .bolusEntry, .carbsEntry:
                        //TODO: Not supporting the processing of remote bolus or carbs yet.
                        //Activate this with more testing.
                        continue
                    default:
                        try await handleCommand(command)
                        await NotificationManager.sendRemoteCommandSuccessNotification(for: command)
                    }
                } catch {
                    self.log.error("Error handling pending command: %{public}@", String(describing: error))
                    await NotificationManager.sendRemoteCommandFailureNotification(for: error)
                }
            }
        } catch {
            self.log.error("Error fetching pending commands: %{public}@", String(describing: error))
        }
        
        await self.endBackgroundTask(backgroundTask)
    }
    
    
    //MARK: Remote Command Persistence
    
    private func commandWasPreviouslyQueued(command: RemoteCommand) throws -> Bool {
        return try handledCommandIDs().contains(where: {$0 == command.id})
    }
    
    private func markCommandAsQueued(command: RemoteCommand) throws {
        var allCommandIds = try handledCommandIDs()
        allCommandIds.append(command.id)
        let jsonData = try JSONEncoder().encode(allCommandIds)
        try jsonData.write(to: commandIDFileURL())
        guard try handledCommandIDs().last == command.id else {
            throw RemoteCommandQueueError.failedCommandIDPersistenceSave
        }
    }
    
    private func handledCommandIDs() throws -> [String] {
        if !FileManager.default.fileExists(atPath: commandIDFileURL().path) {
            return []
        }
        let jsonData = try Data(contentsOf: commandIDFileURL())
        return try JSONDecoder().decode([String].self, from: jsonData)
    }
    
    private func commandIDFileURL() -> URL {
        let docsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: docsPath).appendingPathComponent("handledRemoteCommandIDs.json")
    }
    
    
    //MARK: Push Notifications
    
    func handleRemoteNotification(_ notification: [String: AnyObject]) async {
        
        let backgroundTask = await beginBackgroundTask(name: "Handle Remote Notification")
        do {
            guard let commandSource = commandSource else {
                assertionFailure("Missing command source")
                throw RemoteCommandQueueError.missingCommandSource
            }
            let command = try await commandSource.commandFromPushNotification(notification)
            try await handleCommand(command)
            await NotificationManager.sendRemoteCommandSuccessNotification(for: command)
            log.default("Remote Notification: Finished handling %{public}@", String(describing: notification))
        } catch {
            await NotificationManager.sendRemoteCommandFailureNotification(for: error)
            log.error("Remote Notification: %{public}@. Error: %{public}@", String(describing: notification), String(describing: error))
        }
        
        await endBackgroundTask(backgroundTask)
        
        log.default("Remote Notification: Finished handling")
    }
    
    
    //MARK: Background Task Helpers
    
    func beginBackgroundTask(name: String) async -> UIBackgroundTaskIdentifier? {
        var backgroundTask: UIBackgroundTaskIdentifier?
        backgroundTask = await UIApplication.shared.beginBackgroundTask(withName: name) {
            guard let backgroundTask = backgroundTask else {return}
            Task {
                await UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            
            self.log.error("Background Task Expired: %{public}@", name)
        }
        
        return backgroundTask
    }
    
    func endBackgroundTask(_ backgroundTask: UIBackgroundTaskIdentifier?) async {
        guard let backgroundTask else {return}
        await UIApplication.shared.endBackgroundTask(backgroundTask)
    }
    
}

protocol RemoteCommandSource {
    func commandFromPushNotification(_ notification: [String: AnyObject]) async throws -> RemoteCommand
    func fetchRemoteCommands() async throws -> [RemoteCommand]
    func fetchPendingRemoteCommands() async throws -> [RemoteCommand]
}

protocol RemoteCommandActionDelegate: AnyObject {
    func remoteCommandQueue(_ commandQueue: RemoteCommandQueue, handleCommandAction action: RemoteAction) async throws
}
