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

    fileprivate var carbValue: Int = 15 {
        didSet {
            guard carbValue >= 0 else {
                carbValue = 0
                return
            }

            guard carbValue <= 100 else {
                carbValue = 100
                return
            }

            valueLabel.setText(String(carbValue))
        }
    }

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

    @IBOutlet weak var valueLabel: WKInterfaceLabel!

    @IBOutlet weak var absorptionButtonA: WKInterfaceButton!

    @IBOutlet weak var absorptionButtonB: WKInterfaceButton!

    @IBOutlet weak var absorptionButtonC: WKInterfaceButton!

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
        crownSequencer.delegate = self

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

    @IBAction func decrement() {
        carbValue -= 5
    }

    @IBAction func increment() {
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
            let entry = CarbEntryUserInfo(value: Double(carbValue), absorptionTimeType: absorptionTime, startDate: Date())

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

    fileprivate var accumulatedRotation: Double = 0
}

fileprivate let rotationsPerCarb: Double = 1/24

extension AddCarbsInterfaceController: WKCrownDelegate {
    func crownDidRotate(_ crownSequencer: WKCrownSequencer?, rotationalDelta: Double) {
        accumulatedRotation += rotationalDelta

        let remainder = accumulatedRotation.truncatingRemainder(dividingBy: rotationsPerCarb)
        carbValue += Int((accumulatedRotation - remainder) / rotationsPerCarb)
        accumulatedRotation = remainder
    }
}
