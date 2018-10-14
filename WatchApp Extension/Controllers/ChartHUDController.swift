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
import os.log

final class ChartHUDController: HUDInterfaceController, WKCrownDelegate {
    @IBOutlet weak var glucoseScene: WKInterfaceSKScene!
    @IBAction func setChartWindow1Hour() {
        scene.visibleDuration = .hours(2)
    }
    @IBAction func setChartWindow2Hours() {
        scene.visibleDuration = .hours(4)
    }
    @IBAction func setChartWindow3Hours() {
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

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        if UserDefaults.standard.startPage == .Chart {
            log.default("Switching to start on Chart page")
            becomeCurrentPage()

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

        log.default("didAppear")

        // Force an update when our pixels need to move
        let pixelsWide = scene.size.width * WKInterfaceDevice.current().screenScale
        let pixelInterval = scene.visibleDuration / TimeInterval(pixelsWide)

        timer = Timer.scheduledTimer(withTimeInterval: pixelInterval, repeats: true) { [weak self] _ in
            self?.scene.setNeedsUpdate()
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
            log.default("willActivate() unpausing")
        }

        if !hasInitialActivation && UserDefaults.standard.startPage == .Chart {
            log.default("Switching to start on Chart page")
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

        if glucoseScene.isPaused {
            log.default("update() unpausing")
            glucoseScene.isPaused = false
        }

        updateGlucoseChart()
    }

    func updateGlucoseChart() {
        guard let activeContext = loopManager.activeContext else {
            return
        }

        scene.predictedGlucose = activeContext.predictedGlucose?.values
        scene.correctionRange = loopManager.settings.glucoseTargetRangeSchedule
        scene.unit = activeContext.preferredGlucoseUnit

        loopManager.glucoseStore.getCachedGlucoseSamples(start: .earliestGlucoseCutoff) { (samples) in
            DispatchQueue.main.async {
                self.scene.historicalGlucose = samples
                self.scene.setNeedsUpdate()
            }
        }
    }
}
