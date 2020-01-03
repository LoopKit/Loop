//
//  LoopTuningViewController.swift
//  Loop
//
//  Created by marius eriksen on 12/14/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit
import LoopCore

class LoopTuningViewController: UINavigationController, UINavigationControllerDelegate, IdentifiableClass {
    open override func viewDidLoad() {
        super.viewDidLoad()
//        navigationBar.shadowImage = UIImage()
        delegate = self
      }

    // MARK: - UINavigationControllerDelegate
    open func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
//          let viewControllers = navigationController.viewControllers
//          let count = navigationController.viewControllers.count
    }
}
