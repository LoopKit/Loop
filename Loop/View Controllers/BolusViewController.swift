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
import HealthKit


final class BolusViewController: UITableViewController, IdentifiableClass, UITextFieldDelegate {

    fileprivate enum Rows: Int, CaseCountable {
        case notice = 0
        case eventualGlucose
        case active
        case recommended
        case entry
        case deliver
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // This gets rid of the empty space at the top.
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 0.01))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let spellOutFormatter = NumberFormatter()
        spellOutFormatter.numberStyle = .spellOut

        let amount = bolusRecommendation?.amount ?? 0
        bolusAmountTextField.accessibilityHint = String(format: NSLocalizedString("Recommended Bolus: %@ Units", comment: "Accessibility hint describing recommended bolus units"), spellOutFormatter.string(from: NSNumber(value: amount)) ?? "0")

        bolusAmountTextField.becomeFirstResponder()

        AnalyticsManager.sharedManager.didDisplayBolusScreen()
    }

    func reload() {
        self.tableView.reloadData()
    }

    func generateActiveInsulinDescription(activeInsulin: Double?, pendingInsulin: Double?) -> String
    {
        var rval = ""
        if let iob = activeInsulin, let iobStr = insulinFormatter.string(from: NSNumber(value: iob))
        {
            rval = String(format: NSLocalizedString("Active Insulin %@", comment: "The string format describing active insulin. (1: localized insulin value description)"), iobStr + " U")
        }
        if let pending = pendingInsulin, pending > 0, let pendingStr = insulinFormatter.string(from: NSNumber(value: pending))
        {
            rval += String(format: NSLocalizedString(" (pending: %@)", comment: "The string format appended to active insulin that describes pending insulin. (1: pending insulin)"), pendingStr + " U")
        }
        return rval
    }

    // MARK: - State

    var glucoseUnit: HKUnit = HKUnit.milligramsPerDeciliterUnit()

    var loopError: Error? = nil {
        didSet {
            if let error = loopError {
                noticeLabel?.text = error.localizedDescription
            }
            reload()
        }
    }

    var bolusRecommendation: BolusRecommendation? = nil {
        didSet {
            let amount = bolusRecommendation?.amount ?? 0
            recommendedBolusAmountLabel?.text = bolusUnitsFormatter.string(from: NSNumber(value: amount))
            if let notice = bolusRecommendation?.notice {
                noticeLabel?.text = String(describing: notice)
            } else {
                noticeLabel?.text = nil
            }
            if let pendingInsulin = bolusRecommendation?.pendingInsulin {
                self.pendingInsulin = pendingInsulin
            }
            reload()
        }
    }

    var eventualGlucoseDescription: String? = nil {
        didSet {
            eventualGlucoseLabel?.text = eventualGlucoseDescription
        }
    }

    var eventualGlucose: GlucoseValue? = nil {
        didSet {
            let formatter = NumberFormatter.glucoseFormatter(for: glucoseUnit)
            if let bg = eventualGlucose,
               let bgStr = formatter.string(from: NSNumber(value: bg.quantity.doubleValue(for: glucoseUnit))) {
              eventualGlucoseDescription = String(format: NSLocalizedString("Eventually %@", comment: "The subtitle format describing eventual glucose. (1: localized glucose value description)"), bgStr + " " + glucoseUnit.glucoseUnitDisplayString)
            } else {
                eventualGlucoseDescription = nil
            }
            reload()
       }
    }

    var activeCarbohydratesDescription: String? = nil {
        didSet {
            activeCarbohydratesLabel?.text = activeCarbohydratesDescription
        }
    }

    var activeCarbohydrates: Double? = nil {
        didSet {
            if let cob = activeCarbohydrates, let cobStr = integerFormatter.string(from: NSNumber(value: cob)) {
                activeCarbohydratesDescription = String(format: NSLocalizedString("Active Carbohydrates %@", comment: "The string format describing active carbohydrates. (1: localized glucose value description)"), cobStr + " g")
            } else {
                activeCarbohydratesDescription = nil
            }
            reload()
        }
    }

    var activeInsulinDescription: String? = nil {
        didSet {
            activeInsulinLabel?.text = activeInsulinDescription
        }
    }

    var activeInsulin: Double? = nil {
        didSet {
            activeInsulinDescription = generateActiveInsulinDescription(activeInsulin: activeInsulin, pendingInsulin: pendingInsulin)
            reload()
        }
    }

    var pendingInsulin: Double? = nil {
        didSet {
            activeInsulinDescription = generateActiveInsulinDescription(activeInsulin: activeInsulin, pendingInsulin: pendingInsulin)
            reload()
        }
    }


    var maxBolus: Double = 25

    private(set) var bolus: Double?


    // MARK: - IBOutlets

    @IBOutlet weak var eventualGlucoseLabel: UILabel? {
        didSet {
            eventualGlucoseLabel?.text = eventualGlucoseDescription
        }
    }

    @IBOutlet weak var recommendedBolusAmountLabel: UILabel? {
        didSet {
            let amount = bolusRecommendation?.amount ?? 0
            recommendedBolusAmountLabel?.text = bolusUnitsFormatter.string(from: NSNumber(value: amount))
        }
    }

    @IBOutlet weak var noticeLabel: UILabel? {
        didSet {
            if let error = loopError {
                noticeLabel?.text = error.localizedDescription
            } else if let notice = bolusRecommendation?.notice {
                print("Setting \(notice)")
                noticeLabel?.text = String(describing: notice)
            } else {
                noticeLabel?.text = nil
            }
        }
    }

    @IBOutlet weak var activeCarbohydratesLabel: UILabel? {
        didSet {
            activeCarbohydratesLabel?.text = activeCarbohydratesDescription
        }
    }

    @IBOutlet weak var activeInsulinLabel: UILabel? {
        didSet {
            activeInsulinLabel?.text = activeInsulinDescription
        }
    }

    // MARK: - TableView Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if case .recommended = Rows(rawValue: indexPath.row)! {
            acceptRecommendedBolus();
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if case .recommended = Rows(rawValue: indexPath.row)! {
            cell.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: NSLocalizedString("AcceptRecommendedBolus", comment: "Action to copy the recommended Bolus value to the actual Bolus Field"), target: self, selector: #selector(BolusViewController.acceptRecommendedBolus))
            ]
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Rows(rawValue: indexPath.row)! {
        case .notice:
            let text = noticeLabel?.text
            if text == nil || text!.isEmpty {
                return 0
            }
        case .eventualGlucose:
            let text = eventualGlucoseLabel?.text
            if text == nil || text!.isEmpty {
                return 0
            }
        case .active:
            let cobText = activeCarbohydratesLabel?.text
            let iobText = activeInsulinLabel?.text
            if (cobText == nil || cobText!.isEmpty) && (iobText == nil || iobText!.isEmpty) {
                return 0
            }
        default:
            break
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    @objc
    func acceptRecommendedBolus() {
        bolusAmountTextField?.text = recommendedBolusAmountLabel?.text
    }
    
    
    @IBOutlet weak var bolusAmountTextField: UITextField!

    // MARK: - Actions
   
    @IBAction func authenticateBolus(_ sender: Any) {
        bolusAmountTextField.resignFirstResponder()

        guard let text = bolusAmountTextField?.text, let bolus = bolusUnitsFormatter.number(from: text)?.doubleValue,
            let amountString = bolusUnitsFormatter.string(from: NSNumber(value: bolus)) else {
            return
        }

        guard bolus <= maxBolus else {
            presentAlertController(withTitle: NSLocalizedString("Exceeds Maximum Bolus", comment: "The title of the alert describing a maximum bolus validation error"), message: String(format: NSLocalizedString("The maximum bolus amount is %@ Units", comment: "Body of the alert describing a maximum bolus validation error. (1: The localized max bolus value)"), bolusUnitsFormatter.string(from: NSNumber(value: maxBolus)) ?? ""))
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

    private lazy var bolusUnitsFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()

        numberFormatter.maximumSignificantDigits = 3
        numberFormatter.minimumFractionDigits = 1

        return numberFormatter
    }()


    private lazy var insulinFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()

        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2

        return numberFormatter
    }()

    private lazy var integerFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()

        numberFormatter.numberStyle = .none
        numberFormatter.maximumFractionDigits = 0

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
