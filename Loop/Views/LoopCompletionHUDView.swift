//
//  LoopCompletionHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

final class LoopCompletionHUDView: HUDView {

    @IBOutlet private var loopStateView: LoopStateView!

    override func awakeFromNib() {
        super.awakeFromNib()

        updateDisplay(nil)
    }

    var dosingEnabled = false {
        didSet {
            loopStateView.open = !dosingEnabled
        }
    }

    var lastLoopCompleted: NSDate? {
        didSet {
            updateTimer = nil
            loopInProgress = false
            assertTimer()
        }
    }

    var loopInProgress = false {
        didSet {
            loopStateView.animated = loopInProgress
        }
    }

    func assertTimer(active: Bool = true) {
        if active && window != nil, let date = lastLoopCompleted {
            initTimer(date)
        } else {
            updateTimer = nil
        }
    }

    private func initTimer(startDate: NSDate) {
        let updateInterval = NSTimeInterval(minutes: 1)

        let timer = NSTimer(
            fireDate: startDate.dateByAddingTimeInterval(2),
            interval: updateInterval,
            target: self,
            selector: #selector(updateDisplay(_:)),
            userInfo: nil,
            repeats: true
        )
        updateTimer = timer

        NSRunLoop.mainRunLoop().addTimer(timer, forMode: NSDefaultRunLoopMode)
    }

    private var updateTimer: NSTimer? {
        willSet {
            if let timer = updateTimer {
                timer.invalidate()
            }
        }
    }

    private lazy var formatter: NSDateComponentsFormatter = {
        let formatter = NSDateComponentsFormatter()

        formatter.allowedUnits = [.Hour, .Minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .Short

        return formatter
    }()

    @objc private func updateDisplay(_: NSTimer?) {
        if let date = lastLoopCompleted {
            let ago = abs(min(0, date.timeIntervalSinceNow))

            switch ago {
            case let t where t.minutes <= 5:
                loopStateView.freshness = .Fresh
            case let t where t.minutes <= 15:
                loopStateView.freshness = .Aging
            default:
                loopStateView.freshness = .Stale
            }

            if let timeString = formatter.stringFromTimeInterval(ago) {
                caption.text = String(format: NSLocalizedString("%@ ago", comment: "The description of the time interval since the last completion date. The format string"), timeString)
            } else {
                caption.text = "—"
            }
        } else {
            caption.text = "—"
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        assertTimer()
    }
}
