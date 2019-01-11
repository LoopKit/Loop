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
import HealthKit
import SpriteKit
import os.log

final class ChartHUDController: HUDInterfaceController, WKCrownDelegate {
    @IBOutlet private weak var tableGroup: WKInterfaceGroup!
    @IBOutlet private weak var basalLabel: WKInterfaceLabel!
    @IBOutlet private weak var iobLabel: WKInterfaceLabel!
    @IBOutlet private weak var cobLabel: WKInterfaceLabel!
    @IBOutlet private weak var glucoseScene: WKInterfaceSKScene!
    @IBAction private func setChartWindow1Hour() {
        scene.visibleDuration = .hours(2)
    }
    @IBAction private func setChartWindow2Hours() {
        scene.visibleDuration = .hours(4)
    }
    @IBAction private func setChartWindow3Hours() {
        scene.visibleDuration = .hours(6)
    }
    private let scene = GlucoseChartScene()
    private var timer: Timer? {
        didSet {
            oldValue?.invalidate()
        }
    }
    private let log = OSLog(category: "ChartHUDController")
    private var hasInitialActivation = false

    override init() {
        super.init()

        loopManager = ExtensionDelegate.shared().loopManager
        NotificationCenter.default.addObserver(forName: .GlucoseSamplesDidChange, object: loopManager.glucoseStore, queue: nil) { [weak self] (note) in
            self?.log.default("Received GlucoseSamplesDidChange notification: %{public}@. Updating chart", String(describing: note.userInfo ?? [:]))

            DispatchQueue.main.async {
                self?.updateGlucoseChart()
            }
        }

        glucoseScene.presentScene(scene)
    }

    override func didAppear() {
        super.didAppear()

        if glucoseScene.isPaused {
            log.default("didAppear() unpausing")
            glucoseScene.isPaused = false
        } else {
            log.default("didAppear() not paused")
            glucoseScene.isPaused = false
        }

        // Force an update when our pixels need to move
        let pixelsWide = scene.size.width * WKInterfaceDevice.current().screenScale
        let pixelInterval = scene.visibleDuration / TimeInterval(pixelsWide)

        timer = Timer.scheduledTimer(withTimeInterval: pixelInterval, repeats: true) { [weak self] _ in
            self?.log.default("Timer fired, triggering update")
            self?.scene.setNeedsUpdate()
        }

        if #available(watchOSApplicationExtension 5.0, *) {
            scene.textInsets.left = max(scene.textInsets.left, systemMinimumLayoutMargins.leading)
            scene.textInsets.right = max(scene.textInsets.right, systemMinimumLayoutMargins.trailing)
            tableGroup.setContentInset(UIEdgeInsets(top: 0, left: systemMinimumLayoutMargins.leading, bottom: 0, right: systemMinimumLayoutMargins.trailing))
        }
    }

    override func willDisappear() {
        super.willDisappear()

        log.default("willDisappear")

        timer = nil
    }

    override func willActivate() {
        super.willActivate()

        if glucoseScene.isPaused {
            log.default("willActivate() unpausing")
            glucoseScene.isPaused = false
        } else {
            log.default("willActivate()")
        }

        if !hasInitialActivation && UserDefaults.standard.startOnChartPage {
            log.default("Switching to startOnChartPage")
            becomeCurrentPage()
        }

        hasInitialActivation = true

        loopManager.requestGlucoseBackfillIfNecessary()
    }

    override func didDeactivate() {
        super.didDeactivate()

        log.default("didDeactivate() pausing")
        glucoseScene.isPaused = true
    }

    override func update() {
        super.update()

        guard let activeContext = loopManager.activeContext else {
            return
        }

        if let activeInsulin = activeContext.activeInsulin {
            let insulinFormatter: QuantityFormatter = {
                let insulinFormatter = QuantityFormatter()
                insulinFormatter.numberFormatter.minimumFractionDigits = 1
                insulinFormatter.numberFormatter.maximumFractionDigits = 1

                return insulinFormatter
            }()

            iobLabel.setText(insulinFormatter.string(from: activeInsulin, for: .internationalUnit()))
        } else {
            iobLabel.setText("—")
        }

        if let carbsOnBoard = activeContext.activeCarbohydrates {
            let carbFormatter = QuantityFormatter()
            carbFormatter.numberFormatter.maximumFractionDigits = 0

            cobLabel.setText(carbFormatter.string(from: carbsOnBoard, for: .gram()))
        } else {
            cobLabel.setText("—")
        }

        if let tempBasal = activeContext.lastNetTempBasalDose {
            let basalFormatter = NumberFormatter()
            basalFormatter.numberStyle = .decimal
            basalFormatter.minimumFractionDigits = 1
            basalFormatter.maximumFractionDigits = 3
            basalFormatter.positivePrefix = basalFormatter.plusSign

            let unit = NSLocalizedString(
                "U/hr",
                comment: "The short unit display string for international units of insulin delivery per hour"
            )

            basalLabel.setText(basalFormatter.string(from: tempBasal, unit: unit))
        } else {
            basalLabel.setText("—")
        }

        if glucoseScene.isPaused {
            log.default("update() unpausing")
            glucoseScene.isPaused = false
        }

        updateGlucoseChart()
    }

    func updateGlucoseChart() {
        loopManager.generateChartData { chartData in
            DispatchQueue.main.async {
                self.scene.data = chartData
                self.scene.setNeedsUpdate()
            }
        }
    }
}
