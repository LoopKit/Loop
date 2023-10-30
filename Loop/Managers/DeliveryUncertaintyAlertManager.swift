//
//  DeliveryUncertaintyAlertManager.swift
//  Loop
//
//  Created by Pete Schwamb on 8/31/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import UIKit
import LoopKitUI

class DeliveryUncertaintyAlertManager {
    private let pumpManager: PumpManagerUI
    private let alertPresenter: AlertPresenter
    private var uncertainDeliveryAlert: UIAlertController?

    init(pumpManager: PumpManagerUI, alertPresenter: AlertPresenter) {
        self.pumpManager = pumpManager
        self.alertPresenter = alertPresenter
    }

    private func showUncertainDeliveryRecoveryView() {
        var controller = pumpManager.deliveryUncertaintyRecoveryViewController(colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures)
        controller.completionDelegate = self
        self.alertPresenter.present(controller, animated: true)
    }
    
    func showAlert(animated: Bool = true) {
        if self.uncertainDeliveryAlert == nil {
            let alert = UIAlertController(
                title: NSLocalizedString("Unable To Reach Pump", comment: "Title for alert shown when delivery status is uncertain"),
                message: String(format: NSLocalizedString("%1$@ stopped communicating with your insulin pump during a critical time. Bring your loop hardware close together and wait to see if it resolves (this window will disappear).\n\nIf this window remains unchanged after several minutes, try the usual red loop correction methods.\n\nThe app will continue trying to reach your pump. Insulin delivery information cannot be updated and no automation can continue.\n\nTap on the button below to learn more about other options only if you cannot resolve the problem.", comment: "Message for alert shown when delivery status is uncertain. (1: app name)"), Bundle.main.bundleDisplayName),
                preferredStyle: .alert)
            
            let actionTitle = NSLocalizedString("Learn More", comment: "OK button title for alert shown when delivery status is uncertain")
            let action = UIAlertAction(title: actionTitle, style: .default) { (_) in
                self.uncertainDeliveryAlert = nil
                self.showUncertainDeliveryRecoveryView()
            }
            alert.addAction(action)
            self.alertPresenter.dismissTopMost(animated: false) {
                self.alertPresenter.present(alert, animated: animated)
            }
            self.uncertainDeliveryAlert = alert
        }
    }
    
    func clearAlert() {
        self.uncertainDeliveryAlert?.dismiss(animated: true, completion: nil)
        self.uncertainDeliveryAlert = nil
    }
}


extension DeliveryUncertaintyAlertManager: CompletionDelegate {
    func completionNotifyingDidComplete(_ object: CompletionNotifying) {
        // If delivery still uncertain after recovery view dismissal, present modal alert again.
        if let vc = object as? UIViewController {
            vc.dismiss(animated: true) {
                if self.pumpManager.status.deliveryIsUncertain {
                    self.showAlert(animated: false)
                }
            }
        }
    }
}
