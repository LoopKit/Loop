//
//  RootNavigationController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI

/// The root view controller in Loop
class RootNavigationController: UINavigationController {

    /// Its root view controller is always StatusTableViewController after loading
    var statusTableViewController: StatusTableViewController! {
        return viewControllers.first as? StatusTableViewController
    }
    
    func navigate(to deeplink: Deeplink) {
        switch deeplink {
        case .carbEntry:
            statusTableViewController.presentCarbEntryScreen(nil)
        case .preMeal:
            statusTableViewController.presentPreMealMode()
        case .bolus:
            statusTableViewController.presentBolusScreen()
        case .customPresets:
            statusTableViewController.presentCustomPresets()
        }
    }

    override func restoreUserActivityState(_ activity: NSUserActivity) {
        switch activity.activityType {
        case NSUserActivity.viewLoopStatusActivityType:
            if presentedViewController != nil {
                dismiss(animated: false, completion: nil)
            }

            if viewControllers.count > 1 {
                popToRootViewController(animated: false)
            }
        case NSUserActivity.newCarbEntryActivityType:
            if let navVC = presentedViewController as? UINavigationController {
                if let carbVC = navVC.topViewController as? CarbEntryViewController {
                    carbVC.restoreUserActivityState(activity)
                    return
                } else {
                    dismiss(animated: false, completion: nil)
                }
            }

            if let carbVC = topViewController as? CarbAbsorptionViewController {
                carbVC.restoreUserActivityState(activity)
                return
            } else if viewControllers.count > 1 {
                popToRootViewController(animated: false)
            }

            fallthrough
        default:
            statusTableViewController.restoreUserActivityState(activity)
        }
    }

}
