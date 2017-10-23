//
//  AddCarbsInterfaceController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import WatchConnectivity


final class AddCarbsInterfaceController: WKInterfaceController, IdentifiableClass {

    private var carbValue: Int = 15 {
        didSet {
            guard carbValue >= 0 else {
                carbValue = 0
                return
            }

            guard carbValue <= 100 else {
                carbValue = 100
                return
            }

            carbValueLabel.setText(String(carbValue))
        }
    }

    private let maximumDatePastInterval = TimeInterval(hours: 8)

    private let maximumDateFutureInterval = TimeInterval(hours: 4)

    private var date = Date() {
        didSet {
            let now = Date()
            let minimumDate = now.addingTimeInterval(-maximumDatePastInterval)
            let maximumDate = now.addingTimeInterval(maximumDateFutureInterval)
            if date < minimumDate {
                date = minimumDate
            } else if date > maximumDate {
                date = maximumDate
            }

            dateLabel.setText(dateFormatter.string(from: date))
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var absorptionTime = AbsorptionTimeType.medium {
        didSet {
            absorptionButtonA.setBackgroundColor(UIColor.darkCarbsColor)
            absorptionButtonB.setBackgroundColor(UIColor.darkCarbsColor)
            absorptionButtonC.setBackgroundColor(UIColor.darkCarbsColor)

            switch absorptionTime {
            case .fast:
                absorptionButtonA.setBackgroundColor(UIColor.carbsColor)
            case .medium:
                absorptionButtonB.setBackgroundColor(UIColor.carbsColor)
            case .slow:
                absorptionButtonC.setBackgroundColor(UIColor.carbsColor)
            }
        }
    }

    @IBOutlet var carbValueLabel: WKInterfaceLabel!

    @IBOutlet var minusButton: WKInterfaceButton!

    @IBOutlet var plusButton: WKInterfaceButton!

    @IBOutlet var dateLabel: WKInterfaceLabel!
    
    var activeValueLabel: WKInterfaceLabel! {
        didSet {
            activeValueLabel.setTextColor(UIColor.carbsColor)
            let accessoryColor: UIColor
            switch activeValueLabel {
            case carbValueLabel:
                accessoryColor = UIColor.carbsColor
                dateLabel.setTextColor(UIColor.lightGray)
            case dateLabel:
                accessoryColor = UIColor.lightGray
                carbValueLabel.setTextColor(UIColor.lightGray)
            default:
                accessoryColor = UIColor.black
            }
            minusButton.setTitleWithColor(title: "-", color: accessoryColor)
            plusButton.setTitleWithColor(title: "+", color: accessoryColor)
        }
    }

    @IBOutlet weak var absorptionButtonA: WKInterfaceButton!

    @IBOutlet weak var absorptionButtonB: WKInterfaceButton!

    @IBOutlet weak var absorptionButtonC: WKInterfaceButton!

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
        crownSequencer.delegate = self

        activeValueLabel = carbValueLabel
        date = Date()
        absorptionTime = .medium
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()

        crownSequencer.focus()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    // MARK: - Actions

    @IBAction func decrementCarbValue() {
        activeValueLabel = carbValueLabel
        carbValue -= 5
    }

    @IBAction func incrementCarbValue() {
        activeValueLabel = carbValueLabel
        carbValue += 5
    }

    @IBAction func toggleActiveValueLabel() {
        activeValueLabel = (activeValueLabel === carbValueLabel) ? dateLabel : carbValueLabel
    }

    @IBAction func setAbsorptionTimeFast() {
        absorptionTime = .fast
    }

    @IBAction func setAbsorptionTimeMedium() {
        absorptionTime = .medium
    }

    @IBAction func setAbsorptionTimeSlow() {
        absorptionTime = .slow
    }

    @IBAction func save() {
        if carbValue > 0 {
            let entry = CarbEntryUserInfo(value: Double(carbValue), absorptionTimeType: absorptionTime, startDate: date)

            do {
                try WCSession.default().sendCarbEntryMessage(entry,
                    replyHandler: { (suggestion) in
                        WKExtension.shared().rootInterfaceController?.presentController(withName: BolusInterfaceController.className, context: suggestion)
                    },
                    errorHandler: { (error) in
                        ExtensionDelegate.shared().present(error)
                    }
                )
            } catch {
                presentAlert(withTitle: NSLocalizedString("Send Failed", comment: "The title of the alert controller displayed after a carb entry send attempt fails"),
                    message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a carb entry send attempt fails"),
                    preferredStyle: .alert,
                    actions: [WKAlertAction.dismissAction()]
                )
                return
            }
        }

        dismiss()
    }

    // MARK: - Crown Sequencer

    private var accumulatedRotation: Double = 0
}

private let rotationsPerIncrement: Double = 1/24

extension AddCarbsInterfaceController: WKCrownDelegate {
    func crownDidRotate(_ crownSequencer: WKCrownSequencer?, rotationalDelta: Double) {
        accumulatedRotation += rotationalDelta
        let remainder = accumulatedRotation.truncatingRemainder(dividingBy: rotationsPerIncrement)
        let delta = Int((accumulatedRotation - remainder) / rotationsPerIncrement)

        switch activeValueLabel {
        case carbValueLabel:
            carbValue += delta
        case dateLabel:
            guard let changedDate = Calendar.current.date(byAdding: .minute, value: delta, to: date) else { return }
            date = changedDate
        default:
            break
        }

        accumulatedRotation = remainder
    }
}
