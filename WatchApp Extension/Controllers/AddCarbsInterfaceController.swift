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

            let titleColor = (activeValueButton === carbValueButton) ? UIColor.carbsColor : UIColor.white
            carbValueButton.setTitleWithColor(title: String(carbValue), color: titleColor)
        }
    }

    private var date = Date() {
        didSet {
            let dateDay = Calendar.current.component(.day, from: date)
            let now = Date()
            let currentDay = Calendar.current.component(.day, from: now)
            if dateDay != currentDay {
                let hourAndMinutes = Calendar.current.dateComponents([.hour, .minute], from: date)
                let startOfCurrentDay = Calendar.current.startOfDay(for: now)
                guard let adjustedDate = Calendar.current.date(byAdding: hourAndMinutes, to: startOfCurrentDay) else { return }
                date = adjustedDate
            }

            let titleColor = (activeValueButton === dateButton) ? UIColor.carbsColor : UIColor.white
            dateButton.setTitleWithColor(title: dateFormatter.string(from: date), color: titleColor)
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

    @IBOutlet var carbValueButton: WKInterfaceButton!

    @IBOutlet var minusButton: WKInterfaceButton!

    @IBOutlet var plusButton: WKInterfaceButton!

    @IBOutlet var gramsLabel: WKInterfaceLabel!

    @IBOutlet var dateButton: WKInterfaceButton!

    var activeValueButton: WKInterfaceButton! {
        didSet {
            let carbGroupColor: UIColor
            switch activeValueButton {
            case carbValueButton:
                carbValueButton.setTitleWithColor(title: String(carbValue), color: UIColor.carbsColor)
                carbGroupColor = UIColor.carbsColor
                dateButton.setTitleWithColor(title: dateFormatter.string(from: date), color: UIColor.white)
            case dateButton:
                dateButton.setTitleWithColor(title: dateFormatter.string(from: date), color: UIColor.carbsColor)
                carbValueButton.setTitleWithColor(title: String(carbValue), color: UIColor.white)
                carbGroupColor = UIColor.white
            default:
                carbGroupColor = UIColor.black
            }

            gramsLabel.setTextColor(carbGroupColor)
            plusButton.setTitleWithColor(title: "+", color: carbGroupColor)
            minusButton.setTitleWithColor(title: "-", color: carbGroupColor)
        }
    }

    @IBOutlet weak var absorptionButtonA: WKInterfaceButton!

    @IBOutlet weak var absorptionButtonB: WKInterfaceButton!

    @IBOutlet weak var absorptionButtonC: WKInterfaceButton!

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
        crownSequencer.delegate = self

        activeValueButton = carbValueButton
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

    @IBAction func toggleActiveValueButton() {
        activeValueButton = (activeValueButton === carbValueButton) ? dateButton : carbValueButton
    }

    @IBAction func decrementCarbValue() {
        activeValueButton = carbValueButton
        carbValue -= 5
    }

    @IBAction func incrementCarbValue() {
        activeValueButton = carbValueButton
        carbValue += 5
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

        switch activeValueButton {
        case carbValueButton:
            carbValue += delta
        case dateButton:
            guard let changedDate = Calendar.current.date(byAdding: .minute, value: delta, to: date) else { return }
            date = changedDate
        default:
            break
        }

        accumulatedRotation = remainder
    }
}
