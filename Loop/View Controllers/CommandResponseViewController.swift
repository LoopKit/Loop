//
//  CommandResponseViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/30/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKitUI


extension CommandResponseViewController {
    static func generateDiagnosticReport(dataManager: DeviceDataManager) -> CommandResponseViewController {
        let date = Date()
        let vc = CommandResponseViewController(command: { (completionHandler) in
            dataManager.loopManager.generateDiagnosticReport { (report) in
                DispatchQueue.main.async {
                    completionHandler([
                        "Use the Share button above save this diagnostic report to aid investigating your problem. Issues can be filed at https://github.com/LoopKit/Loop/issues.",
                        "Generated: \(date)",
                        "",
                        String(reflecting: dataManager),
                        "",
                        report,
                        "",
                    ].joined(separator: "\n\n"))
                }
            }

            return NSLocalizedString("Loading...", comment: "The loading message for the diagnostic report screen")
        })
        vc.fileName = "Loop Report \(ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withSpaceBetweenDateAndTime, .withInternetDateTime])).md"

        return vc
    }
}
