//
//  PopoverInNavigationControllerSegue.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/11/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class PopoverInNavigationControllerSegue: UIStoryboardSegue, UIPopoverPresentationControllerDelegate {
    override func perform() {
        destinationViewController.popoverPresentationController?.delegate = self

        super.perform()
    }

    // MARK: - UIPopoverPresentationControllerDelegate

    func presentationController(controller: UIPresentationController, viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle) -> UIViewController? {
        return UINavigationController(rootViewController: controller.presentedViewController)
    }
}
