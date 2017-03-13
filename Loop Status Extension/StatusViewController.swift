//
//  StatusViewController.swift
//  Loop Status Extension
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import CoreData
import HealthKit
import LoopUI
import NotificationCenter
import UIKit

class StatusViewController: UIViewController, NCWidgetProviding {

    @IBOutlet weak var hudView: HUDView! {
        didSet {
            hudView.loopCompletionHUD.stateColors = .loopStatus
            hudView.glucoseHUD.stateColors = .cgmStatus
            hudView.glucoseHUD.tintColor = .glucoseTintColor
            hudView.basalRateHUD.tintColor = .doseTintColor
            hudView.reservoirVolumeHUD.stateColors = .pumpStatus
            hudView.batteryHUD.stateColors = .pumpStatus
        }
    }
    @IBOutlet weak var subtitleLabel: UILabel!

    var statusExtensionContext: StatusExtensionContext?
    var defaults: UserDefaults?
    final var observationContext = 1

    var loopCompletionHUD: LoopCompletionHUDView! {
        get {
            return hudView.loopCompletionHUD
        }
    }

    var glucoseHUD: GlucoseHUDView! {
        get {
            return hudView.glucoseHUD
        }
    }

    var basalRateHUD: BasalRateHUDView! {
        get {
            return hudView.basalRateHUD
        }
    }

    var reservoirVolumeHUD: ReservoirVolumeHUDView! {
        get {
            return hudView.reservoirVolumeHUD
        }
    }

    var batteryHUD: BatteryLevelHUDView! {
        get {
            return hudView.batteryHUD
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        subtitleLabel.alpha = 0
        subtitleLabel.textColor = .subtitleLabelColor

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openLoopApp(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)

        defaults = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)
        if let defaults = defaults {
            defaults.addObserver(
                self,
                forKeyPath: defaults.statusExtensionContextObservableKey,
                options: [],
                context: &observationContext
            )
        }
    }
    
    deinit {
        if let defaults = defaults {
            defaults.removeObserver(self, forKeyPath: defaults.statusExtensionContextObservableKey, context: &observationContext)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &observationContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        update()
    }
    
    @objc private func openLoopApp(_: Any) {
        if let url = Bundle.main.mainAppUrl {
            self.extensionContext?.open(url)
        }
    }

    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        let result = update()
        completionHandler(result)
    }
    
    @discardableResult
    func update() -> NCUpdateResult {
        guard let context = defaults?.statusExtensionContext else {
            return NCUpdateResult.failed
        }
        
        if let glucose = context.latestGlucose {
            glucoseHUD.setGlucoseQuantity(glucose.value,
               at: glucose.startDate,
               unit: glucose.unit,
               sensor: glucose.sensor
            )
        }
        
        if let batteryPercentage = context.batteryPercentage {
            batteryHUD.batteryLevel = Double(batteryPercentage)
        }
        
        if let reservoir = context.reservoir {
            reservoirVolumeHUD.reservoirLevel = min(1, max(0, Double(reservoir.unitVolume / Double(reservoir.capacity))))
            reservoirVolumeHUD.setReservoirVolume(volume: reservoir.unitVolume, at: reservoir.startDate)
        }

        if let netBasal = context.netBasal {
            basalRateHUD.setNetBasalRate(netBasal.rate, percent: netBasal.percentage, at: netBasal.startDate)
        }

        if let loop = context.loop {
            loopCompletionHUD.dosingEnabled = loop.dosingEnabled
            loopCompletionHUD.lastLoopCompleted = loop.lastCompleted
        }

        subtitleLabel.alpha = 0

        if let eventualGlucose = context.eventualGlucose {
            let formatter = NumberFormatter.glucoseFormatter(for: eventualGlucose.unit)

            if let eventualGlucoseNumberString = formatter.string(from: NSNumber(value: eventualGlucose.value)) {
                subtitleLabel.text = String(
                    format: NSLocalizedString(
                        "Eventually %1$@ %2$@",
                        comment: "The subtitle format describing eventual glucose. (1: localized glucose value description) (2: localized glucose units description)"),
                    eventualGlucoseNumberString,
                    eventualGlucose.unit.glucoseUnitDisplayString
                )
                subtitleLabel.alpha = 1
            }
        }
        
        // Right now we always act as if there's new data.
        // TODO: keep track of data changes and return .noData if necessary
        return NCUpdateResult.newData
    }
}
