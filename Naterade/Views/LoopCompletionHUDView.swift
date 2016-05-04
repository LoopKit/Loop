//
//  LoopCompletionHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class LoopCompletionHUDView: HUDView {

    override func awakeFromNib() {
        super.awakeFromNib()

        updateCaption(nil)
    }

    var lastLoopCompleted: NSDate? {
        didSet {
            assertTimer()
        }
    }

    func assertTimer() {
        if window != nil && updateTimer == nil, let date = lastLoopCompleted {
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
            selector: #selector(updateCaption(_:)),
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

    @objc private func updateCaption(_: NSTimer?) {
        if let date = lastLoopCompleted, ago = formatter.stringFromTimeInterval(abs(min(0, date.timeIntervalSinceNow))) {
            caption.text = String(format: NSLocalizedString("%@ ago", comment: "The description of the time interval since the last completion date. The format string"), ago)
        } else {
            caption.text = nil
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        assertTimer()
    }
}
