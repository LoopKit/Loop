//
//  AddCarbsInterfaceController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import WatchConnectivity
import HealthKit
import LoopKit
import os.log


final class AddCarbsInterfaceController: WKInterfaceController, IdentifiableClass {

    private var carbValue: Int = 15 {
        didSet {
            if carbValue < minimumCarbValue {
                carbValue = minimumCarbValue
            } else if carbValue > maximumCarbValue {
                carbValue = maximumCarbValue
            }

            valueLabel.setText(String(carbValue))
        }
    }

    private let minimumCarbValue = 0
    private let maximumCarbValue = 100

    private let maximumDatePastInterval = TimeInterval(hours: 8)
    private let maximumDateFutureInterval = TimeInterval(hours: 4)

    private var date = Date() {
        didSet {
            let now = Date()
            let minimumDate = now - maximumDatePastInterval
            let maximumDate = now + maximumDateFutureInterval

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

    private var absorptionTime: AbsorptionTimeType = .medium {
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

    @IBOutlet var valueLabel: WKInterfaceLabel!

    @IBOutlet var dateLabel: WKInterfaceLabel!

    @IBOutlet weak var absorptionButtonA: WKInterfaceButton!

    @IBOutlet weak var absorptionButtonB: WKInterfaceButton!

    @IBOutlet weak var absorptionButtonC: WKInterfaceButton!

    private enum InputMode {
        case value
        case date
    }

    private var inputMode: InputMode = .value {
        didSet {
            switch inputMode {
            case .value:
                valueLabel.setTextColor(UIColor.carbsColor)
                dateLabel.setTextColor(UIColor.lightGray)
            case .date:
                valueLabel.setTextColor(UIColor.lightGray)
                dateLabel.setTextColor(UIColor.carbsColor)
            }
        }
    }

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
        crownSequencer.delegate = self

        date = Date()
        absorptionTime = .medium
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }

    override func didAppear() {
        super.didAppear()

        updateNewCarbEntryUserActivity()

        crownSequencer.focus()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    // MARK: - Actions

    private let valueIncrement = 5
    private let dateIncrement = TimeInterval(minutes: 15)

    @IBAction func decrement() {
        switch inputMode {
        case .value:
            carbValue -= valueIncrement
        case .date:
            date -= dateIncrement
        }

        WKInterfaceDevice.current().play(.directionDown)
    }

    @IBAction func increment() {
        switch inputMode {
        case .value:
            carbValue += valueIncrement
        case .date:
            date += dateIncrement
        }

        WKInterfaceDevice.current().play(.directionUp)
    }

    @IBAction func toggleInputMode() {
        inputMode = (inputMode == .value) ? .date : .value
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
                try WCSession.default.sendCarbEntryMessage(entry,
                    replyHandler: { (suggestion) in
                        DispatchQueue.main.async {
                            WKInterfaceDevice.current().play(.success)

                            ExtensionDelegate.shared().loopManager.addConfirmedCarbEntry(entry)

                            WKExtension.shared().rootInterfaceController?.presentController(withName: BolusInterfaceController.className, context: suggestion)
                        }
                    },
                    errorHandler: { (error) in
                        DispatchQueue.main.async {
                            WKInterfaceDevice.current().play(.failure)
                            ExtensionDelegate.shared().present(error)
                        }
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

        switch inputMode {
        case .value:
            carbValue += delta
        case .date:
            date += TimeInterval(minutes: Double(delta))
        }

        accumulatedRotation = remainder
    }
}

extension AddCarbsInterfaceController: NSUserActivityDelegate {
    func updateNewCarbEntryUserActivity() {
        if #available(watchOSApplicationExtension 5.0, *) {
            let userActivity = NSUserActivity.forDidAddCarbEntryOnWatch()
            update(userActivity)
        } else {
            let userActivity = NSUserActivity.forNewCarbEntry()
            userActivity.update(from: entry)
            updateUserActivity(userActivity.activityType, userInfo: userActivity.userInfo, webpageURL: nil)
        }
    }

    private var entry: NewCarbEntry {
        return NewCarbEntry(quantity: HKQuantity(unit: .gram(), doubleValue: Double(carbValue)), startDate: date, foodType: nil, absorptionTime: nil)
    }
}
