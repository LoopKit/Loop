//
//  LoopCompletionHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

final class LoopCompletionHUDView: HUDView {

    @IBOutlet private weak var loopStateView: LoopStateView!

    override func awakeFromNib() {
        super.awakeFromNib()

        updateDisplay(nil)
    }

    var dosingEnabled = false {
        didSet {
            loopStateView.open = !dosingEnabled
        }
    }

    var lastLoopCompleted: Date? {
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

    func assertTimer(_ active: Bool = true) {
        if active && window != nil, let date = lastLoopCompleted {
            initTimer(date)
        } else {
            updateTimer = nil
        }
    }

    private func initTimer(_ startDate: Date) {
        let updateInterval = TimeInterval(minutes: 1)

        let timer = Timer(
            fireAt: startDate.addingTimeInterval(2),
            interval: updateInterval,
            target: self,
            selector: #selector(updateDisplay(_:)),
            userInfo: nil,
            repeats: true
        )
        updateTimer = timer

        RunLoop.main.add(timer, forMode: RunLoopMode.defaultRunLoopMode)
    }

    private var updateTimer: Timer? {
        willSet {
            if let timer = updateTimer {
                timer.invalidate()
            }
        }
    }

    private lazy var formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .short

        return formatter
    }()

    @objc private func updateDisplay(_: Timer?) {
        if let date = lastLoopCompleted {
            let ago = abs(min(0, date.timeIntervalSinceNow))

            switch ago {
            case let t where t.minutes <= 5:
                loopStateView.freshness = .fresh
            case let t where t.minutes <= 15:
                loopStateView.freshness = .aging
            default:
                loopStateView.freshness = .stale
            }

            if let timeString = formatter.string(from: ago) {
                caption.text = String(format: NSLocalizedString("%@ ago", comment: "Format string describing the time interval since the last completion date. (1: The localized date components"), timeString)
                accessibilityLabel = String(format: NSLocalizedString("Loop ran %@ ago", comment: "Accessbility format label describing the time interval since the last completion date. (1: The localized date components)"), timeString)
            } else {
                caption.text = "—"
                accessibilityLabel = nil
            }
        } else {
            caption.text = "—"
            accessibilityLabel = NSLocalizedString("Waiting for first run", comment: "Acessibility label describing completion HUD waiting for first run")
        }

        if dosingEnabled {
            accessibilityHint = NSLocalizedString("Closed loop", comment: "Accessibility hint describing completion HUD for a closed loop")
        } else {
            accessibilityHint = NSLocalizedString("Open loop", comment: "Accessbility hint describing completion HUD for an open loop")
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        assertTimer()
    }
}
