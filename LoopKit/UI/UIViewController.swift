//
//  UIViewController.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/16/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIViewController {
    /**
     Convenience method to display an error object in an alert controller

     - parameter error:      The error to display
     - parameter animated:   Whether to animate the alert
     - parameter completion: An optional closure to execute after the presentation finishes
     */
    public func presentAlertControllerWithError(error: ErrorType, animated: Bool = true, completion: (() -> Void)? = nil) {

        // See: https://forums.developer.apple.com/thread/17431
        // The compiler automatically emits the code necessary to translate between any ErrorType and NSError.
        let castedError: NSError = error as NSError

        let alert = UIAlertController(
            title: castedError.userInfo[NSLocalizedDescriptionKey] as? String ?? NSLocalizedString("com.loudnate.LoopKit.errorAlertDefaultTitle", tableName: "LoopKit", value: "Error", comment: "The default title for an alert displaying an error"),
            message: castedError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String ?? NSLocalizedString("com.loudnate.LoopKit.errorAlertDefaultMessage", tableName: "LoopKit", value: "Please try again", comment: "The default message for an alert displaying an error"),
            preferredStyle: .Alert
        )

        let action = UIAlertAction(
            title: NSLocalizedString("com.loudnate.LoopKit.errorAlertActionTitle", tableName: "LoopKit", value: "OK", comment: "The title of the action used to dismiss an error alert"),
            style: .Default,
            handler: nil
        )

        alert.addAction(action)
        alert.preferredAction = action

        self.presentViewController(alert, animated: animated, completion: completion)
    }
}