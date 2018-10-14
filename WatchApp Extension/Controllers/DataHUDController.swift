//
//  DataHUDController.swift
//  Loop
//
//  Created by Bharat Mediratta on 10/12/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import WatchKit
import WatchConnectivity
import CGMBLEKit
import LoopKit
import SpriteKit
import os.log

final class DataHUDController: HUDInterfaceController {
    @IBOutlet weak var basalLabel: WKInterfaceLabel!
    @IBOutlet weak var iobLabel: WKInterfaceLabel!
    @IBOutlet weak var cobLabel: WKInterfaceLabel!

    private let log = OSLog(category: "DataHUDController")
    private var hasInitialActivation = false

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        if UserDefaults.standard.startPage == .Data {
            log.default("Switching to start on Data page")
            becomeCurrentPage()
        }
    }

    override func willActivate() {
        super.willActivate()

        if !hasInitialActivation && UserDefaults.standard.startPage == .Data {
            log.default("Switching to start on Data page")
            becomeCurrentPage()
        }

        hasInitialActivation = true
    }

    override func update() {
        super.update()

        guard let activeContext = loopManager.activeContext else {
            return
        }

        let insulinFormatter: NumberFormatter = {
            let numberFormatter = NumberFormatter()

            numberFormatter.numberStyle = .decimal
            numberFormatter.minimumFractionDigits = 1
            numberFormatter.maximumFractionDigits = 1

            return numberFormatter
        }()

        if let activeInsulin = activeContext.iob, let valueStr = insulinFormatter.string(from: activeInsulin) {
            iobLabel.setText(String(format: NSLocalizedString(
                    "%1$@ U",
                    comment: "The subtitle format describing units of active insulin. (1: localized insulin value description)"
                ),
                valueStr
            ))
        }

        if let carbsOnBoard = activeContext.cob {
            let carbFormatter = NumberFormatter()
            carbFormatter.numberStyle = .decimal
            carbFormatter.maximumFractionDigits = 0
            let valueStr = carbFormatter.string(from: carbsOnBoard)

            cobLabel.setText(String(format: NSLocalizedString(
                    "%1$@ g",
                    comment: "The subtitle format describing grams of active carbs. (1: localized carb value description)"
                ),
                valueStr!
            ))
        }

        if let tempBasal = activeContext.lastNetTempBasalDose {
            let basalFormatter = NumberFormatter()
            basalFormatter.numberStyle = .decimal
            basalFormatter.minimumFractionDigits = 1
            basalFormatter.maximumFractionDigits = 3
            basalFormatter.positivePrefix = basalFormatter.plusSign
            let valueStr = basalFormatter.string(from: tempBasal)

            let basalLabelText = String(format: NSLocalizedString(
                "%1$@ U/hr",
                comment: "The subtitle format describing the current temp basal rate. (1: localized basal rate description)"),
                                      valueStr!)
            basalLabel.setText(basalLabelText)
        }
    }
}
