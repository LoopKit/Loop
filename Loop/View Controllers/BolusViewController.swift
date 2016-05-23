//
//  BolusViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/11/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LocalAuthentication
import LoopKit


class BolusViewController: UITableViewController, IdentifiableClass, UITextFieldDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        bolusAmountTextField.becomeFirstResponder()
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        AnalyticsManager.didDisplayBolusScreen()
    }

    var recommendedBolus: Double = 0 {
        didSet {
            recommendedBolusAmountLabel?.text = decimalFormatter.stringFromNumber(recommendedBolus)
        }
    }

    private(set) var bolus: Double?

    @IBOutlet weak var recommendedBolusAmountLabel: UILabel? {
        didSet {
            recommendedBolusAmountLabel?.text = decimalFormatter.stringFromNumber(recommendedBolus)
        }
    }

    @IBOutlet weak var bolusAmountTextField: UITextField!

    // MARK: - Actions

    @IBAction func authenticateBolus(sender: AnyObject) {
        bolusAmountTextField.resignFirstResponder()

        let context = LAContext()

        if context.canEvaluatePolicy(.DeviceOwnerAuthentication, error: nil) {
            context.evaluatePolicy(.DeviceOwnerAuthentication,
                                   localizedReason: NSLocalizedString("Please authenticate to bolus", comment: "The message displayed during a device authentication prompt for bolus specification"),
                                   reply: { (success, error) in
                if success {
                    self.setBolusAndClose(sender)
                }
            })
        } else {
            setBolusAndClose(sender)
        }
    }

    private func setBolusAndClose(sender: AnyObject) {
        if let text = bolusAmountTextField?.text, bolus = decimalFormatter.numberFromString(text)?.doubleValue {
            self.bolus = bolus

            self.performSegueWithIdentifier("close", sender: sender)
        }
    }

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)
    }

    private lazy var decimalFormatter: NSNumberFormatter = {
        let numberFormatter = NSNumberFormatter()

        numberFormatter.maximumSignificantDigits = 3
        numberFormatter.minimumFractionDigits = 1

        return numberFormatter
    }()

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(textField: UITextField) -> Bool {
        textField.resignFirstResponder()

        return true
    }
}
