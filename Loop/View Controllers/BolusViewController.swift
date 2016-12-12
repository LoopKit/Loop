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

        let spellOutFormatter = NumberFormatter()
        spellOutFormatter.numberStyle = .spellOut

        bolusAmountTextField.accessibilityHint = String(format: NSLocalizedString("Recommended Bolus: %@ Units", comment: "Accessibility hint describing recommended bolus units"), spellOutFormatter.string(from: NSNumber(value: recommendedBolus)) ?? "0")

        bolusAmountTextField.becomeFirstResponder()
    
        AnalyticsManager.sharedManager.didDisplayBolusScreen()
    }

    var recommendedBolus: Double = 0 {
        didSet {
            recommendedBolusAmountLabel?.text = decimalFormatter.string(from: NSNumber(value: recommendedBolus))
        }
    }

    var maxBolus: Double = 25

    private(set) var bolus: Double?

    @IBOutlet weak var recommendedBolusAmountLabel: UILabel? {
        didSet {
            recommendedBolusAmountLabel?.text = decimalFormatter.string(from: NSNumber(value: recommendedBolus))
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if (indexPath.row == 0) {
            acceptRecommendedBolus();
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if (indexPath.row == 0) {
            cell.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: NSLocalizedString("AcceptRecommendedBolus", comment: "Action to copy the recommended Bolus value to the actual Bolus Field"), target: self, selector: #selector(BolusViewController.acceptRecommendedBolus))
            ]
        }
    }
    
    @objc
    func acceptRecommendedBolus() {
        bolusAmountTextField?.text = recommendedBolusAmountLabel?.text
    }
    
    
    @IBOutlet weak var bolusAmountTextField: UITextField!

    // MARK: - Actions
   
    @IBAction func authenticateBolus(_ sender: Any) {
        bolusAmountTextField.resignFirstResponder()

        guard let text = bolusAmountTextField?.text, let bolus = decimalFormatter.number(from: text)?.doubleValue,
            let amountString = decimalFormatter.string(from: NSNumber(value: bolus)) else {
            return
        }

        guard bolus <= maxBolus else {
            presentAlertController(withTitle: NSLocalizedString("Exceeds Maximum Bolus", comment: "The title of the alert describing a maximum bolus validation error"), message: String(format: NSLocalizedString("The maximum bolus amount is %@ Units", comment: "Body of the alert describing a maximum bolus validation error. (1: The localized max bolus value)"), decimalFormatter.string(from: NSNumber(value: maxBolus)) ?? ""))
            return
        }

        let context = LAContext()

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: String(format: NSLocalizedString("Authenticate to Bolus %@ Units", comment: "The message displayed during a device authentication prompt for bolus specification"), amountString),
                                   reply: { (success, error) in
                if success {
                    self.setBolusAndClose(bolus)
                }
            })
        } else {
            setBolusAndClose(bolus)
        }
    }

    private func setBolusAndClose(_ bolus: Double) {
        self.bolus = bolus

        self.performSegue(withIdentifier: "close", sender: nil)
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
