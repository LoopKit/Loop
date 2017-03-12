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
    
    private func roundedBolus(_ bolus: Double) -> Double {
        return round(bolus * 10) / 10
    }
    
    @IBAction func authenticateBolus(_ sender: Any) {
        bolusAmountTextField.resignFirstResponder()

        guard let text = bolusAmountTextField?.text, let bolus = decimalFormatter.number(from: text)?.doubleValue,
            let amountString = decimalFormatter.string(from: NSNumber(value: bolus)) else {
            return
        }
        
        let rounded_bolus = roundedBolus(bolus)
        guard rounded_bolus == bolus else {
            bolusAmountTextField?.text = "\(rounded_bolus)"
            presentAlertController(withTitle: NSLocalizedString("Rounded Bolus", comment: "The title of the alert describing a rounded bolus validation error"), message: String(format: NSLocalizedString("The bolus amount has to be a multiple of 0.1, please try again.", comment: "Body of the alert describing a rounding bolus validation error.")))
            return
        }
        
        guard bolus >= 0 else {
            presentAlertController(withTitle: NSLocalizedString("Negative Bolus", comment: "The title of the alert describing a negative bolus validation error"), message: String(format: NSLocalizedString("The bolus amount is negative", comment: "Body of the alert describing a negative bolus validation error.")))
            return
        }
        
        guard bolus <= maxBolus else {
            presentAlertController(withTitle: NSLocalizedString("Exceeds Maximum Bolus", comment: "The title of the alert describing a maximum bolus validation error"), message: String(format: NSLocalizedString("The maximum bolus amount is %@ Units", comment: "Body of the alert describing a maximum bolus validation error. (1: The localized max bolus value)"), decimalFormatter.string(from: NSNumber(value: maxBolus)) ?? ""))
            return
        }

        guard bolus <= recommendedBolus else {
            //1. Create the alert controller.
            let alert = UIAlertController(title: "Exceeds Recommended Bolus", message: "The bolus amount of \(bolus) U is higher than the recommended amount of \(recommendedBolus) U. Please re-enter the amount to confirm.", preferredStyle: .alert)
            
            //2. Add the text field. You can configure it however you need.
            alert.addTextField { (textField) in
                textField.text = ""
                textField.keyboardType = UIKeyboardType.decimalPad
                textField.autocorrectionType = UITextAutocorrectionType.no
            }
            // 3. Grab the value from the text field, and print it when the user clicks OK.
            alert.addAction(UIAlertAction(title: "Deliver", style: .default, handler: { [weak alert] (_) in
                //let result = alert?.textFields![0].text // Force unwrapping because we know it exists.
                let wanted = "\(bolus)"
                let result = alert?.textFields![0].text
                if result != nil && result! == wanted {
                    self.setBolusAndClose(bolus)
                } else {
                    self.presentAlertController(withTitle: NSLocalizedString("Exceeds Recommended Bolus", comment: "The title of the alert describing a recommended bolus validation error"), message: String(format: NSLocalizedString("The Validation failed (Recommended \(self.recommendedBolus), wanted \(wanted), entered \(result!))", comment: "Body of the alert describing a recommended bolus validation error. (1: The localized recommended bolus value)")))
                    return
                }
            }))
            
            alert.addAction(UIAlertAction(title: "Back", style: .default, handler: nil))
            
            // 4. Present the alert.
            self.present(alert, animated: true, completion: nil)
            
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
