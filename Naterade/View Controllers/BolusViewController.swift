//
//  BolusViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/11/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit


class BolusViewController: UITableViewController, IdentifiableClass, UITextFieldDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        bolusAmountTextField.becomeFirstResponder()
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

    @IBAction func deliverBolus(sender: AnyObject) {
        bolusAmountTextField.resignFirstResponder()

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
