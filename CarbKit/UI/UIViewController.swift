//
//  UIViewController.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/16/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension UIViewController {
    func presentAlertControllerWithError(error: NSError, animated: Bool = true, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(
            title: error.userInfo[NSLocalizedDescriptionKey] as? String ?? "Error",
            message: error.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String ?? "",
            preferredStyle: .Alert
        )

        let action = UIAlertAction(
            title: NSLocalizedString("com.loudnate.CarbKit.errorAlertActionTitle", tableName: "CarbKit", value: "OK", comment: "The title of the action used to dismiss an error alert"),
            style: .Default,
            handler: nil
        )

        alert.addAction(action)
        alert.preferredAction = action

        self.presentViewController(alert, animated: animated, completion: completion)
    }
}