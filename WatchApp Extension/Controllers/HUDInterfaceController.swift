//
//  HUDInterfaceController.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 6/29/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import WatchKit

class HUDInterfaceController: WKInterfaceController {
    private var activeContextObserver: NSObjectProtocol?

    @IBOutlet weak var loopHUDImage: WKInterfaceImage!
    @IBOutlet weak var loopTimer: WKInterfaceTimer!
    @IBOutlet weak var glucoseLabel: WKInterfaceLabel!
    @IBOutlet weak var eventualGlucoseLabel: WKInterfaceLabel!

    weak var loopManager: LoopDataManager?

    override init() {
        loopManager = ExtensionDelegate.shared().loopManager
    }

    override func willActivate() {
        super.willActivate()

        if activeContextObserver == nil {
            activeContextObserver = NotificationCenter.default.addObserver(forName: .ContextUpdated, object: nil, queue: nil) { _ in
                DispatchQueue.main.async {
                    self.update()
                }
            }
        }
    }

    override func didAppear() {
        update()
    }

    func update() {
        guard let activeContext = loopManager?.activeContext, let date = activeContext.loopLastRunDate else {
            loopHUDImage.setLoopImage(.unknown)
            loopTimer.setHidden(true)
            return
        }

        loopTimer.setDate(date)
        loopTimer.setHidden(false)
        loopTimer.start()

        glucoseLabel.setHidden(true)
        eventualGlucoseLabel.setHidden(true)
        if let glucose = activeContext.glucose, let unit = activeContext.preferredGlucoseUnit {
            let formatter = NumberFormatter.glucoseFormatter(for: unit)

            if let glucoseValue = formatter.string(from: glucose.doubleValue(for: unit)) {
                let trend = activeContext.glucoseTrend?.symbol ?? ""
                glucoseLabel.setText(glucoseValue + trend)
                glucoseLabel.setHidden(false)
            }

            if let eventualGlucose = activeContext.eventualGlucose {
                let glucoseValue = formatter.string(from: eventualGlucose.doubleValue(for: unit))
                eventualGlucoseLabel.setText(glucoseValue)
                eventualGlucoseLabel.setHidden(false)
            }
        }

        loopHUDImage.setLoopImage({
            switch date.timeIntervalSinceNow {
            case let t where t > .minutes(-6):
                return .fresh
            case let t where t > .minutes(-20):
                return .aging
            default:
                return .stale
            }
        }())
    }
}
