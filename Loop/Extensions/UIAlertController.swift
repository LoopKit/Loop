//
//  UIAlertController.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI


extension UIAlertController {
    /**
     Initializes an ActionSheet-styled controller for selecting a workout duration
     
     - parameter handler: A closure to execute when the sheet is dismissed after selection. The closure has a single argument:
        - endDate: The date at which the user selected the workout to end
     */
    convenience init(workoutDurationSelectionHandler handler: @escaping (_ endDate: Date) -> Void) {
        self.init(
            title: NSLocalizedString("Use Workout Glucose Targets", comment: "The title of the alert controller used to select a duration for workout targets"),
            message: nil,
            preferredStyle: .actionSheet
        )

        let formatter = DateComponentsFormatter()
        formatter.allowsFractionalUnits = false
        formatter.unitsStyle = .full

        for interval in [1, 2].map({ TimeInterval(hours: $0) }) {
            let duration = NSLocalizedString("For %1$@", comment: "The format string used to describe a finite workout targets duration")

            addAction(UIAlertAction(title: String(format: duration, formatter.string(from: interval)!), style: .default) { _ in
                handler(Date(timeIntervalSinceNow: interval))
            })
        }

        let distantFuture = NSLocalizedString("Indefinitely", comment: "The title of a target alert action specifying an indefinitely long workout targets duration")
        addAction(UIAlertAction(title: distantFuture, style: .default) { _ in
            handler(Date.distantFuture)
        })

        addCancelAction()
    }

    /// Initializes an action sheet-styled controller for selecting a PumpManager
    ///
    /// - Parameters:
    ///   - cgmManagers: An array of PumpManagers
    ///   - selectionHandler: A closure to execute when a manager is selected
    ///   - manager: The selected manager
    convenience init(pumpManagers: [PumpManagerUI.Type], selectionHandler: @escaping (_ manager: PumpManagerUI.Type) -> Void) {
        self.init(
            title: NSLocalizedString("Add Pump", comment: "Action sheet title selecting Pump"),
            message: nil,
            preferredStyle: .actionSheet
        )

        for manager in pumpManagers {
            addAction(UIAlertAction(
                title: manager.localizedTitle,
                style: .default,
                handler: { (_) in
                    selectionHandler(manager)
                }
            ))
        }
    }

    /// Initializes an action sheet-styled controller for selecting a CGMManager
    ///
    /// - Parameters:
    ///   - cgmManagers: An array of CGMManager-conforming types
    ///   - pumpManager: A PumpManager/CGMManager combo instance
    ///   - selectionHandler: A closure to execute when either a new CGMManager or the current PumpManager is selected
    ///   - cgmManager: The selected CGMManager type
    ///   - pumpManager: The selected PumpManager instance
    convenience init(cgmManagers: [CGMManagerUI.Type], pumpManager: CGMManager?, selectionHandler: @escaping (_ cgmManager: CGMManagerUI.Type?, _ pumpManager: CGMManager?) -> Void) {
        self.init(
            title: NSLocalizedString("Add CGM", comment: "Action sheet title selecting CGM"),
            message: nil,
            preferredStyle: .actionSheet
        )

        if let pumpManager = pumpManager {
            addAction(UIAlertAction(
                title: pumpManager.localizedTitle,
                style: .default,
                handler: { (_) in
                    selectionHandler(nil, pumpManager)
                }
            ))
        }

        for manager in cgmManagers {
            addAction(UIAlertAction(
                title: manager.localizedTitle,
                style: .default,
                handler: { (_) in
                    selectionHandler(manager, nil)
                }
            ))
        }
    }

    convenience init(deleteCGMManagerHandler handler: @escaping (_ isDeleted: Bool) -> Void) {
        self.init(
            title: nil,
            message: NSLocalizedString("Are you sure you want to delete this CGM?", comment: "Confirmation message for deleting a CGM"),
            preferredStyle: .actionSheet
        )

        addAction(UIAlertAction(
            title: NSLocalizedString("Delete CGM", comment: "Button title to delete CGM"),
            style: .destructive,
            handler: { (_) in
                handler(true)
            }
        ))

        addCancelAction { (_) in
            handler(false)
        }
    }

    func addCancelAction(handler: ((UIAlertAction) -> Void)? = nil) {
        let cancel = NSLocalizedString("Cancel", comment: "The title of the cancel action in an action sheet")
        addAction(UIAlertAction(title: cancel, style: .cancel, handler: handler))
    }
}
