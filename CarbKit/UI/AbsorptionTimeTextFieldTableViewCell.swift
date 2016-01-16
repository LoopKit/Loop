//
//  AbsorptionTimeTextFieldTableViewCell.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class AbsorptionTimeTextFieldTableViewCell: DecimalTextFieldTableViewCell {

    override var numberFormatter: NSNumberFormatter {
        didSet {
            numberFormatter.numberStyle = .NoStyle
        }
    }

    var segmentValues: [Double] = []

    var segmentedControlInputAccessoryView: SegmentedControlInputAccessoryView?

    func selectedSegmentChanged(sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case let x where x < segmentValues.count:
            textField.text = numberFormatter.stringFromNumber(NSNumber(double: segmentValues[x]))
            delegate?.textFieldTableViewCellDidUpdateText(self)
        default:
            break
        }
    }

    func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
        textField.inputAccessoryView = segmentedControlInputAccessoryView

        segmentedControlInputAccessoryView?.segmentedControl?.addTarget(self, action: "selectedSegmentChanged:", forControlEvents: .ValueChanged)

        return true
    }

    override func textFieldDidEndEditing(textField: UITextField) {
        super.textFieldDidEndEditing(textField)

        segmentedControlInputAccessoryView?.segmentedControl?.removeTarget(self, action: "selectedSegmentChanged:", forControlEvents: .ValueChanged)
    }

    func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
        segmentedControlInputAccessoryView?.segmentedControl?.selectedSegmentIndex = -1

        return true
    }
}
