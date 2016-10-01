//
//  CommandResponseViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/30/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit


extension CommandResponseViewController {
    static func generateDiagnosticReport(dataManager: DeviceDataManager) -> CommandResponseViewController {
        let vc = CommandResponseViewController(command: { (completionHandler) in
            let group = DispatchGroup()

            var doseStoreResponse = ""
            group.enter()
            dataManager.doseStore.generateDiagnosticReport { (report) in
                doseStoreResponse = report
                group.leave()
            }

            var carbStoreResponse = ""
            if let carbStore = dataManager.carbStore {
                group.enter()
                carbStore.generateDiagnosticReport { (report) in
                    carbStoreResponse = report
                    group.leave()
                }
            }

            var glucoseStoreResponse = ""
            if let glucoseStore = dataManager.glucoseStore {
                group.enter()
                glucoseStore.generateDiagnosticReport { (report) in
                    glucoseStoreResponse = report
                    group.leave()
                }
            }

            // LoopStatus
            var loopManagerResponse = ""
            group.enter()
            dataManager.loopManager.generateDiagnosticReport { (report) in
                loopManagerResponse = report
                group.leave()
            }

            group.notify(queue: DispatchQueue.main) {
                completionHandler([
                    "Use the Share button above save this diagnostic report to aid investigating your problem. Issues can be filed at https://github.com/LoopKit/Loop/issues.",
                    "Generated: \(Date())",
                    String(reflecting: dataManager),
                    loopManagerResponse,
                    doseStoreResponse,
                    carbStoreResponse,
                    glucoseStoreResponse
                ].joined(separator: "\n\n"))
            }

            return NSLocalizedString("Loading...", comment: "The loading message for the diagnostic report screen")
        })

        return vc
    }
}
