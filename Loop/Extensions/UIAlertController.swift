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
        - duration: The duration for which the workout is to be enabled
     */
    internal convenience init(workoutDurationSelectionHandler handler: @escaping (_ duration: TimeInterval) -> Void) {
        self.init(
            title: NSLocalizedString("Use Workout Preset", comment: "The title of the alert controller used to select a duration for workout targets"),
            message: nil,
            preferredStyle: .actionSheet
        )

        let formatter = DateComponentsFormatter()
        formatter.allowsFractionalUnits = false
        formatter.unitsStyle = .full

        for interval in [1, 2].map({ TimeInterval(hours: $0) }) {
            let duration = NSLocalizedString("For %1$@", comment: "The format string used to describe a finite workout targets duration")

            addAction(UIAlertAction(title: String(format: duration, formatter.string(from: interval)!), style: .default) { _ in
                handler(interval)
            })
        }

        let distantFuture = NSLocalizedString("Until I turn off", comment: "The title of a target alert action specifying workout targets duration until it is turned off by the user")
        addAction(UIAlertAction(title: distantFuture, style: .default) { _ in
            handler(.infinity)
        })

        addCancelAction()
    }
    
    /**
     Initializes an ActionSheet-styled controller for selecting a pre-meal preset duration
     
     - parameter handler: A closure to execute when the sheet is dismissed after selection. The closure has a single argument:
        - duration: The duration for which the pre-meal preset is to be enabled
     */
    internal convenience init(premealDurationSelectionHandler handler: @escaping (_ duration: TimeInterval) -> Void) {
        self.init(
            title: NSLocalizedString("Use Pre-Meal Preset", comment: "The title of the alert controller used to select a duration for pre-meal targets"),
            message: nil,
            preferredStyle: .actionSheet
        )

        let distantFuture = NSLocalizedString("Until I enter carbs", comment: "The title of a target alert action specifying pre-meal targets duration for 1 hour or until the user enters carbs (whichever comes first).")
        addAction(UIAlertAction(title: distantFuture, style: .default) { _ in
            handler(.hours(1))
        })

        addCancelAction()
    }

    /// Initializes an action sheet-styled controller for selecting a PumpManager
    ///
    /// - Parameters:
    ///   - availablePumpManagers: An array of available PumpManagers
    ///   - selectionHandler: A closure to execute when a manager is selected
    ///   - identifier: Identifier of the selected PumpManager
    internal convenience init(availablePumpManagers: [PumpManagerDescriptor], selectionHandler: @escaping (_ identifier: String) -> Void) {
        self.init(
            title: NSLocalizedString("Add Pump", comment: "Action sheet title selecting Pump"),
            message: nil,
            preferredStyle: .actionSheet
        )

        for availablePumpManager in availablePumpManagers {
            addAction(UIAlertAction(
                title: availablePumpManager.localizedTitle,
                style: .default,
                handler: { (_) in
                    selectionHandler(availablePumpManager.identifier)
                }
            ))
        }
    }

    /// Initializes an action sheet-styled controller for selecting a CGMManager
    ///
    /// - Parameters:
    ///   - availableCGMManagers: An array of available CGMManagers
    ///   - selectionHandler: A closure to execute when either a new CGMManager or the current PumpManager is selected
    ///   - identifier: Identifier of the selected CGMManager
    internal convenience init(availableCGMManagers: [CGMManagerDescriptor], selectionHandler: @escaping (_ identifier: String) -> Void) {
        self.init(
            title: NSLocalizedString("Add CGM", comment: "Action sheet title selecting CGM"),
            message: nil,
            preferredStyle: .actionSheet
        )
        
        for availableCGMManager in availableCGMManagers.sorted(by: {$0.localizedTitle < $1.localizedTitle}) {
            addAction(UIAlertAction(
                title: availableCGMManager.localizedTitle,
                style: .default,
                handler: { (_) in
                    selectionHandler(availableCGMManager.identifier)
            }
            ))
        }
    }

    internal convenience init(deleteCGMManagerHandler handler: @escaping (_ isDeleted: Bool) -> Void) {
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

    /// Initializes an action sheet-styled controller for selecting a service.
    ///
    /// - Parameters:
    ///   - availableServices: An array of available services.
    ///   - selectionHandler: A closure to execute when a service is selected.
    ///   - identifier: The identifier of the selected service.
    internal convenience init(availableServices: [ServiceDescriptor], selectionHandler: @escaping (_ identifier: String) -> Void) {
        self.init(
            title: NSLocalizedString("Add Service", comment: "Action sheet title selecting service"),
            message: nil,
            preferredStyle: .actionSheet
        )

        for availableService in availableServices {
            addAction(UIAlertAction(
                title: availableService.localizedTitle,
                style: .default,
                handler: { (_) in
                    selectionHandler(availableService.identifier)
                }
            ))
        }
    }

    internal func addCancelAction(handler: ((UIAlertAction) -> Void)? = nil) {
        let cancel = NSLocalizedString("Cancel", comment: "The title of the cancel action in an action sheet")
        addAction(UIAlertAction(title: cancel, style: .cancel, handler: handler))
    }
}


// Adapted from https://oleb.net/2018/uialertcontroller-textfield/
extension UIAlertController {
    public enum TextInputResult {
        /// The user tapped Cancel.
        case cancel
        /// The user tapped the OK button. The payload is the text they entered in the text field.
        case ok(String)
    }

    /// Creates a fully configured alert controller with one text field for text input, a Cancel and
    /// and an OK button.
    ///
    /// - Parameters:
    ///   - title: The title of the alert view.
    ///   - message: The message of the alert view.
    ///   - cancelButtonTitle: The title of the Cancel button.
    ///   - okButtonTitle: The title of the OK button.
    ///   - isValid: The OK button will be disabled as long as the entered text doesn't pass
    ///     the validation. By default, all entered text is considered valid.
    ///   - textFieldConfiguration: Use this to configure the text field (e.g. set placeholder text).
    ///   - onCompletion: Called when the user closes the alert view. The argument tells you whether
    ///     the user tapped the Close or the OK button (in which case this delivers the entered text).
    public convenience init(title: String, message: String? = nil,
                            cancelButtonTitle: String, okButtonTitle: String,
                            validate isValid: @escaping (String) -> Bool = { _ in true },
                            textFieldConfiguration: ((UITextField) -> Void)? = nil,
                            onCompletion: @escaping (TextInputResult) -> Void) {
        self.init(title: title, message: message, preferredStyle: .alert)

        /// Observes a UITextField for various events and reports them via callbacks.
        /// Sets itself as the text field's delegate and target-action target.
        class TextFieldObserver: NSObject, UITextFieldDelegate {
            let textFieldValueChanged: (UITextField) -> Void
            let textFieldShouldReturn: (UITextField) -> Bool

            init(textField: UITextField, valueChanged: @escaping (UITextField) -> Void, shouldReturn: @escaping (UITextField) -> Bool) {
                self.textFieldValueChanged = valueChanged
                self.textFieldShouldReturn = shouldReturn
                super.init()
                textField.delegate = self
                textField.addTarget(self, action: #selector(TextFieldObserver.textFieldValueChanged(sender:)), for: .editingChanged)
            }

            @objc func textFieldValueChanged(sender: UITextField) {
                textFieldValueChanged(sender)
            }

            // MARK: UITextFieldDelegate
            func textFieldShouldReturn(_ textField: UITextField) -> Bool {
                return textFieldShouldReturn(textField)
            }
        }

        var textFieldObserver: TextFieldObserver?

        // Every `UIAlertAction` handler must eventually call this
        func finish(result: TextInputResult) {
            // Capture the observer to keep it alive while the alert is on screen
            // Check for non-nil first to suppress an unused variable warning
            if textFieldObserver != nil {
                textFieldObserver = nil
            }
            onCompletion(result)
        }

        let cancelAction = UIAlertAction(title: cancelButtonTitle, style: .cancel, handler: { _ in
            finish(result: .cancel)
        })
        let okAction = UIAlertAction(title: okButtonTitle, style: .default, handler: { [unowned self] _ in
            finish(result: .ok(self.textFields?.first?.text ?? ""))
        })
        addAction(cancelAction)
        addAction(okAction)
        preferredAction = okAction

        addTextField(configurationHandler: { textField in
            textFieldConfiguration?(textField)
            textFieldObserver = TextFieldObserver(textField: textField,
                valueChanged: { textField in
                    okAction.isEnabled = isValid(textField.text ?? "")
                },
                shouldReturn: { textField in
                    isValid(textField.text ?? "")
                })
        })
        // Start with a disabled OK button if necessary
        okAction.isEnabled = isValid(textFields?.first?.text ?? "")
    }
}
