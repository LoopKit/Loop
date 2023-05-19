//
//  ResetLoopManager.swift
//  Loop
//
//  Created by Cameron Ingham on 5/18/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit

protocol ResetLoopManagerDelegate: AnyObject {
    func loopWillReset()
    func loopDidReset()
    
    func presentConfirmationAlert(
        confirmAction: @escaping (_ pumpManager: PumpManager?, _ completion: @escaping () -> Void) -> Void,
        cancelAction: @escaping () -> Void
    )
    
    func presentCouldNotResetLoopAlert(error: Error)
}

class ResetLoopManager {
    
    private weak var delegate: ResetLoopManagerDelegate?
    
    private var loopIsAlreadyReset: Bool = false
    private var resetAlertPresented: Bool = false
    
    init(delegate: ResetLoopManagerDelegate?) {
        self.delegate = delegate
        
        checkIfLoopIsAlreadyReset()
    }
    
    func askUserToConfirmLoopReset() {
        if loopIsAlreadyReset {
            UserDefaults.appGroup?.userRequestedLoopReset = false
        }
        
        if UserDefaults.appGroup?.userRequestedLoopReset == true && !resetAlertPresented {
            resetAlertPresented = true
            
            delegate?.presentConfirmationAlert(
                confirmAction: { [weak self] pumpManager, completion in
                    self?.resetAlertPresented = false
                    
                    guard let pumpManager else {
                        self?.resetLoop()
                        completion()
                        return
                    }
                    
                    pumpManager.prepareForDeactivation() { [weak self] error in
                        guard let error = error else {
                            self?.resetLoop()
                            completion()
                            return
                        }
                        
                        self?.delegate?.presentCouldNotResetLoopAlert(error: error)
                    }
                }, cancelAction: { [weak self] in
                    self?.resetAlertPresented = false
                    UserDefaults.appGroup?.userRequestedLoopReset = false
                }
            )
        }
        
        checkIfLoopIsAlreadyReset()
    }
    
    private func checkIfLoopIsAlreadyReset() {
        let fileManager = FileManager.default
        
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        guard let hasReset = try? fileManager.contentsOfDirectory(atPath: url.path).count <= 1 else {
            return
        }
        
        loopIsAlreadyReset = hasReset
    }
    
    private func resetLoop() {
        delegate?.loopWillReset()
        
        resetLoopDocuments()
        resetLoopUserDefaults()
        
        delegate?.loopDidReset()
    }
    
    private func resetLoopUserDefaults() {
        // Store values to persist
        let allowDebugFeatures = UserDefaults.appGroup?.allowDebugFeatures

        // Wipe away whole domain
        UserDefaults.appGroup?.removePersistentDomain(forName: Bundle.main.appGroupSuiteName)

        // Restore values to persist
        UserDefaults.appGroup?.allowDebugFeatures = allowDebugFeatures ?? false
    }
    
    private func resetLoopDocuments() {
        guard let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Bundle.main.appGroupSuiteName) else {
            preconditionFailure("Could not get a container directory URL. Please ensure App Groups are set up correctly in entitlements.")
        }
        
        let documents: URL = directoryURL.appendingPathComponent("com.loopkit.LoopKit", isDirectory: true)
        try? FileManager.default.removeItem(at: documents)
        
        guard let localDocuments = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            preconditionFailure("Could not get a documents directory URL.")
        }
        try? FileManager.default.removeItem(at: localDocuments)
    }
}
