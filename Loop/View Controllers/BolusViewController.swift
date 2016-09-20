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


final class BolusViewController: UITableViewController, IdentifiableClass, UITextFieldDelegate {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        bolusAmountTextField.becomeFirstResponder()

        AnalyticsManager.sharedManager.didDisplayBolusScreen()
    }

    var recommendedBolus: Double = 0 {
        didSet {
            recommendedBolusAmountLabel?.text = decimalFormatter.string(from: NSNumber(value: recommendedBolus))
        }
    }

    private(set) var bolus: Double?

    @IBOutlet weak var recommendedBolusAmountLabel: UILabel? {
        didSet {
            recommendedBolusAmountLabel?.text = decimalFormatter.string(from: NSNumber(value: recommendedBolus))
        }
    }

    @IBOutlet weak var bolusAmountTextField: UITextField!

    // MARK: - Actions

    @IBAction func authenticateBolus(_ sender: Any) {
        bolusAmountTextField.resignFirstResponder()

        let context = LAContext()

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            context.evaluatePolicy(.deviceOwnerAuthentication,
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

    private func setBolusAndClose(_ sender: Any) {
        if let text = bolusAmountTextField?.text, let bolus = decimalFormatter.number(from: text)?.doubleValue {
            self.bolus = bolus

            self.performSegue(withIdentifier: "close", sender: sender)
        }
    }

    private lazy var decimalFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()

        numberFormatter.maximumSignificantDigits = 3
        numberFormatter.minimumFractionDigits = 1

        return numberFormatter
    }()

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        bolusAmountTextField.resignFirstResponder()
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()

        return true
    }
}
