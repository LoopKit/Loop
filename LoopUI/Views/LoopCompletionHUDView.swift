//
//  LoopCompletionHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKitUI
import LoopCore

public final class LoopCompletionHUDView: BaseHUDView {

    @IBOutlet private weak var loopStateView: LoopStateView!
    
    override public var orderPriority: HUDViewOrderPriority {
        return 1
    }

    private(set) var freshness = LoopCompletionFreshness.unknown {
        didSet {
            updateTintColor()
        }
    }

    override public func awakeFromNib() {
        super.awakeFromNib()

        updateDisplay(nil)
    }

    public var dosingEnabled = false {
        didSet {
            loopStateView.open = !dosingEnabled
        }
    }

    public var lastLoopCompleted: Date? {
        didSet {
            if lastLoopCompleted != oldValue {
                loopInProgress = false
            }
        }
    }

    public var loopInProgress = false {
        didSet {
            loopStateView.animated = loopInProgress

            if !loopInProgress {
                updateTimer = nil
                assertTimer()
            }
        }
    }

    public func assertTimer(_ active: Bool = true) {
        if active && window != nil, let date = lastLoopCompleted {
            initTimer(date)
        } else {
            updateTimer = nil
        }
    }

    override public func stateColorsDidUpdate() {
        super.stateColorsDidUpdate()
        updateTintColor()
    }

    private func updateTintColor() {
        let tintColor: UIColor?

        switch freshness {
        case .fresh:
            tintColor = stateColors?.normal
        case .aging:
            tintColor = stateColors?.warning
        case .stale:
            tintColor = stateColors?.error
        case .unknown:
            tintColor = stateColors?.unknown
        }

        self.tintColor = tintColor
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

        RunLoop.main.add(timer, forMode: .default)
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

        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .short

        return formatter
    }()

    @objc private func updateDisplay(_: Timer?) {
        if let date = lastLoopCompleted {
            let ago = abs(min(0, date.timeIntervalSinceNow))
            
            freshness = LoopCompletionFreshness(age: ago)

            if let timeString = formatter.string(from: ago) {
                switch traitCollection.preferredContentSizeCategory {
                case UIContentSizeCategory.extraSmall,
                     UIContentSizeCategory.small,
                     UIContentSizeCategory.medium,
                     UIContentSizeCategory.large:
                    // Use a longer form only for smaller text sizes
                    caption.text = String(format: LocalizedString("%@ ago", comment: "Format string describing the time interval since the last completion date. (1: The localized date components"), timeString)
                default:
                    caption.text = timeString
                }

                accessibilityLabel = String(format: LocalizedString("Loop ran %@ ago", comment: "Accessbility format label describing the time interval since the last completion date. (1: The localized date components)"), timeString)
            } else {
                caption.text = "—"
                accessibilityLabel = nil
            }
        } else {
            caption.text = "—"
            accessibilityLabel = LocalizedString("Waiting for first run", comment: "Acessibility label describing completion HUD waiting for first run")
        }

        if dosingEnabled {
            accessibilityHint = LocalizedString("Closed loop", comment: "Accessibility hint describing completion HUD for a closed loop")
        } else {
            accessibilityHint = LocalizedString("Open loop", comment: "Accessbility hint describing completion HUD for an open loop")
        }
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()

        assertTimer()
    }
}
