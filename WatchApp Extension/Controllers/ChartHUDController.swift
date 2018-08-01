//
//  ChartHUDController.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/26/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import WatchKit
import WatchConnectivity
import CGMBLEKit
import LoopKit
import SpriteKit

final class ChartHUDController: HUDInterfaceController, WKCrownDelegate {
    @IBOutlet weak var basalLabel: WKInterfaceLabel!
    @IBOutlet weak var iobLabel: WKInterfaceLabel!
    @IBOutlet weak var cobLabel: WKInterfaceLabel!
    @IBOutlet weak var glucoseScene: WKInterfaceSKScene!
    @IBAction func setChartWindow1Hour() {
        scene.visibleHours = 1
    }
    @IBAction func setChartWindow2Hours() {
        scene.visibleHours = 2
    }
    @IBAction func setChartWindow3Hours() {
        scene.visibleHours = 3
    }
    private let scene = GlucoseChartScene()

    override init() {
        super.init()

        loopManager = ExtensionDelegate.shared().loopManager
        NotificationCenter.default.addObserver(forName: .GlucoseSamplesDidChange, object: loopManager?.glucoseStore, queue: nil) { _ in
            DispatchQueue.main.async {
                self.updateGlucoseChart()
            }
        }

        glucoseScene.presentScene(scene)
    }

    override func awake(withContext context: Any?) {
        if UserDefaults.standard.startOnChartPage {
            self.becomeCurrentPage()

            // For some reason, .didAppear() does not get called when we do this. It gets called *twice* the next
            // time this view appears. Force it by hand now, until we figure out the root cause.
            //
            // TODO: possibly because I'm not calling super.awake()? investigate that.
            DispatchQueue.main.async {
                self.didAppear()
            }
        }
    }

    override func didAppear() {
        super.didAppear()
    }

    override func willActivate() {
        crownSequencer.delegate = self
        crownSequencer.focus()

        super.willActivate()

        loopManager?.glucoseStore.maybeRequestGlucoseBackfill()
        glucoseScene.isPaused = false
    }

    override func update() {
        super.update()

        guard let activeContext = loopManager?.activeContext else {
            return
        }

        let insulinFormatter: NumberFormatter = {
            let numberFormatter = NumberFormatter()

            numberFormatter.numberStyle = .decimal
            numberFormatter.minimumFractionDigits = 1
            numberFormatter.maximumFractionDigits = 1

            return numberFormatter
        }()

        iobLabel.setHidden(true)
        if let activeInsulin = activeContext.IOB, let valueStr = insulinFormatter.string(from:NSNumber(value:activeInsulin)) {
            iobLabel.setText(String(format: NSLocalizedString(
                "IOB %1$@ U",
                comment: "The subtitle format describing units of active insulin. (1: localized insulin value description)"),
                                       valueStr))
            iobLabel.setHidden(false)
        }

        cobLabel.setHidden(true)
        if let carbsOnBoard = activeContext.COB {
            let carbFormatter = NumberFormatter()
            carbFormatter.numberStyle = .decimal
            carbFormatter.maximumFractionDigits = 0
            let valueStr = carbFormatter.string(from:NSNumber(value:carbsOnBoard))

            cobLabel.setText(String(format: NSLocalizedString(
                "COB %1$@ g",
                comment: "The subtitle format describing grams of active carbs. (1: localized carb value description)"),
                                      valueStr!))
            cobLabel.setHidden(false)
        }

        basalLabel.setHidden(true)
        if let tempBasal = activeContext.lastNetTempBasalDose {
            let basalFormatter = NumberFormatter()
            basalFormatter.numberStyle = .decimal
            basalFormatter.minimumFractionDigits = 1
            basalFormatter.maximumFractionDigits = 3
            basalFormatter.positivePrefix = basalFormatter.plusSign
            let valueStr = basalFormatter.string(from:NSNumber(value:tempBasal))

            let basalLabelText = String(format: NSLocalizedString(
                "%1$@ U/hr",
                comment: "The subtitle format describing the current temp basal rate. (1: localized basal rate description)"),
                                      valueStr!)
            basalLabel.setText(basalLabelText)
            basalLabel.setHidden(false)
        }

        updateGlucoseChart()
    }

    func updateGlucoseChart() {
        guard let activeContext = loopManager?.activeContext else {
            return
        }

        scene.predictedGlucose = activeContext.predictedGlucose?.values
        scene.targetRanges = activeContext.targetRanges
        scene.temporaryOverride = activeContext.temporaryOverride
        scene.unit = activeContext.preferredGlucoseUnit

        loopManager?.glucoseStore.getCachedGlucoseSamples(start: .EarliestGlucoseCutoff) { (samples) in
            DispatchQueue.main.async {
                self.scene.historicalGlucose = samples
                self.scene.updateNodes(animated: false)
            }
        }
    }

    // MARK: WKCrownDelegate
    var crownAccumulator = 0.0

    func crownDidRotate(_ crownSequencer: WKCrownSequencer?, rotationalDelta: Double) {
        crownAccumulator += rotationalDelta
        if abs(crownAccumulator) >= 0.25 {
            scene.visibleBg += Int(sign(crownAccumulator))
            crownAccumulator = 0
        }
    }
}
