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
import SwiftCharts

class StatusViewController: UIViewController, NCWidgetProviding {

    @IBOutlet weak var hudView: HUDView!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var glucoseChartContentView: ChartContentView!

    private lazy var charts: StatusChartsManager = {
        let charts = StatusChartsManager()

        charts.glucoseDisplayRange = (
            min: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: 100),
            max: HKQuantity(unit: HKUnit.milligramsPerDeciliterUnit(), doubleValue: 175)
        )

        return charts
    }()

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
        subtitleLabel.textColor = UIColor.secondaryLabelColor

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(openLoopApp(_:)))
        view.addGestureRecognizer(tapGestureRecognizer)

        defaults = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)
        if let defaults = defaults {
            defaults.addObserver(
                self,
                forKeyPath: defaults.statusExtensionContextObservableKey,
                options: [],
                context: &observationContext)
        }

        glucoseChartContentView.chartGenerator = { [unowned self] (frame) in
            return self.charts.glucoseChartWithFrame(frame)?.view
        }

        self.extensionContext?.widgetLargestAvailableDisplayMode = NCWidgetDisplayMode.expanded
    }

    deinit {
        if let defaults = defaults {
            defaults.removeObserver(self, forKeyPath: defaults.statusExtensionContextObservableKey, context: &observationContext)
        }
    }
    
    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        if (activeDisplayMode == NCWidgetDisplayMode.compact) {
            self.preferredContentSize = maxSize
        } else {
            self.preferredContentSize = CGSize(width: maxSize.width, height: 200)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &observationContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        update()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
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
        guard
            let context = defaults?.statusExtensionContext
        else {
            return NCUpdateResult.failed
        }
        
        // We should never have the case where there's glucose values but no preferred
        // unit. However, if that case were to happen we might show quantities against
        // the wrong units and that could be very harmful. So unless there's a preferred
        // unit, assume that none of the rest of the data is reliable.
        guard
            let preferredUnitString = context.preferredUnitString
        else {
            return NCUpdateResult.failed
        }

        if let lastGlucose = context.glucose?.last {
            glucoseHUD.set(glucoseQuantity: lastGlucose.quantity,
                           at: lastGlucose.startDate,
                           unitString: preferredUnitString,
                           from: context.sensor)
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

        let preferredUnit = HKUnit(from: preferredUnitString)
        let formatter = NumberFormatter.glucoseFormatter(for: preferredUnit)
        if let eventualGlucose = context.eventualGlucose,
           let eventualGlucoseNumberString = formatter.string(from: NSNumber(value: eventualGlucose)) {
            subtitleLabel.text = String(
                    format: NSLocalizedString(
                        "Eventually %1$@ %2$@",
                        comment: "The subtitle format describing eventual glucose. (1: localized glucose value description) (2: localized glucose units description)"),
                    eventualGlucoseNumberString,
                    preferredUnit.glucoseUnitDisplayString)
            subtitleLabel.alpha = 1
        } else {
            subtitleLabel.alpha = 0
        }

        let dateFormatter: DateFormatter = {
            let timeFormatter = DateFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short

            return timeFormatter
        }()


        if let glucose = context.glucose {
            let glucoseFormatter = NumberFormatter.glucoseFormatter(for: preferredUnit)

            charts.glucosePoints = glucose.map {
                ChartPoint(
                    x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                    y: ChartAxisValueDoubleUnit(Double($0.quantity), unitString: preferredUnitString, formatter: glucoseFormatter)
                )
            }

            if let predictedGlucose = context.predictedGlucose {
                charts.predictedGlucosePoints = predictedGlucose.map {
                    ChartPoint(
                        x: ChartAxisValueDate(date: $0.startDate, formatter: dateFormatter),
                        y: ChartAxisValueDoubleUnit(Double($0.quantity), unitString: preferredUnitString, formatter: glucoseFormatter)
                    )
                }
            }
            
            charts.prerender()
            glucoseChartContentView.reloadChart()
        }

        // Right now we always act as if there's new data.
        // TODO: keep track of data changes and return .noData if necessary
        return NCUpdateResult.newData
    }
}
