//
//  LoopCompletionHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit
import LoopKitUI

public final class LoopCompletionHUDView: BaseHUDView {

    @IBOutlet private weak var loopStateView: LoopStateView!
    
    override public var orderPriority: HUDViewOrderPriority {
        return 2
    }

    private(set) var freshness = LoopCompletionFreshness.stale {
        didSet {
            loopStateView.freshness = freshness
            updateLabelColor()
        }
    }
    
    private var freshnessColor: UIColor {
        switch freshness {
        case .fresh: return .label
        case .aging: return loopStatusColors.warning
        case .stale: return loopStatusColors.error
        }
    }
    
    private func updateLabelColor() {
        caption?.textColor = freshnessColor
    }

    override public func awakeFromNib() {
        super.awakeFromNib()

        updateDisplay(nil)
    }

    public var loopStatusColors: StateColorPalette = StateColorPalette(unknown: .black, normal: .black, warning: .black, error: .black) {
        didSet {
            loopStateView.loopStatusColors = loopStatusColors
        }
    }
    
    public var loopIconClosed = false {
        didSet {
            loopStateView.open = !loopIconClosed
        }
    }

    public var lastLoopCompleted: Date? {
        didSet {
            if lastLoopCompleted != oldValue {
                loopInProgress = false
            }
        }
    }
    
    public var deviceIssue: Bool = false {
        didSet {
            loopStateView.deviceIssue = deviceIssue
        }
    }

    /// The loop is running on another device (the pod is loaned to the watch); do not age.
    public var loopRunsElsewhere = false {
        didSet {
            if loopRunsElsewhere != oldValue {
                updateDisplay(nil)
            }
        }
    }
    
    public var mostRecentGlucoseDataDate: Date?
    public var mostRecentPumpDataDate: Date?

    public var loopInProgress = false {
        didSet {
            if !loopInProgress {
                updateTimer = nil
                assertTimer()
            }
        }
    }

    public var closedLoopDisallowedLocalizedDescription: String?

    public var onAgoUpdate: ((TimeInterval?) -> Void)?

    public func assertTimer(_ active: Bool = true) {
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

        RunLoop.main.add(timer, forMode: .default)
    }

    private var updateTimer: Timer? {
        willSet {
            if let timer = updateTimer {
                timer.invalidate()
            }
        }
    }

    private lazy var formatterFull: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full

        return formatter
    }()

    private var lastLoopMessage: String = ""

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private lazy var timeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter
    }()

    @objc private func updateDisplay(_: Timer?) {
        lastLoopMessage = ""
        caption?.isHidden = !loopIconClosed
        let timeAgoToIncludeTimeStamp: TimeInterval = .minutes(20)
        let timeAgoToIncludeDate: TimeInterval = .hours(4)
        if loopRunsElsewhere {
            freshness = .fresh
            onAgoUpdate?(nil)
            caption?.text = ""
            accessibilityLabel = LocalizedString("Loop is running on Apple Watch", comment: "Accessibility label describing completion HUD while the watch runs the loop")
        } else if loopIconClosed, let date = lastLoopCompleted {
            // restrict time ago from 0 to 7 days
            let ago = min(abs(min(0, date.timeIntervalSinceNow)), TimeInterval.days(7))

            freshness = LoopCompletionFreshness(age: ago)
            onAgoUpdate?(ago)

            if let timeString = ago.truncatedTimeAgoString {
                switch traitCollection.preferredContentSizeCategory {
                case UIContentSizeCategory.extraSmall,
                     UIContentSizeCategory.small,
                     UIContentSizeCategory.medium,
                     UIContentSizeCategory.large:
                    // Use a longer form only for smaller text sizes
                    caption?.attributedText = formattedTimeAgoString(timeString, includeGreaterThan: ago > .hours(1))
                default:
                    caption?.text = timeString
                }

                accessibilityLabel = String(format: LocalizedString("Loop ran %@ ago", comment: "Accessbility format label describing the time interval since the last completion date. (1: The localized date components)"), timeString)

                var fullTimeStr: String = ""
                if ago >= timeAgoToIncludeDate {
                    fullTimeStr = String(format: LocalizedString("was at %1$@", comment: "Format string describing last completion. (1: the date"), timeDateFormatter.string(from: date))
                } else if ago >= timeAgoToIncludeTimeStamp {
                    fullTimeStr = String(format: LocalizedString("%1$@ ago at %2$@", comment: "Format string describing last completion. (1: time ago, (2: the date"), ago.truncatedTimeAgoString!, timeFormatter.string(from: date))
                } else if ago < .minutes(1) {
                    fullTimeStr = String(format: LocalizedString("<1 min ago", comment: "Format string describing last completion"))
                } else {
                    fullTimeStr = String(format: LocalizedString("%1$@ ago", comment: "Format string describing last completion. (1: time ago"), ago.truncatedTimeAgoString!)
                }
                lastLoopMessage = String(format: LocalizedString("Last completed loop %1$@.", comment: "Last loop time completed message (1: last loop time string)"), fullTimeStr)
            } else {
                caption?.text = "–"
                accessibilityLabel = nil
            }
        } else if !loopIconClosed, let mostRecentPumpDataDate, let mostRecentGlucoseDataDate {
            onAgoUpdate?(nil)
            let ago = max(abs(min(0, mostRecentPumpDataDate.timeIntervalSinceNow)), abs(min(0, mostRecentGlucoseDataDate.timeIntervalSinceNow)))

            // when closed loop is off, always present fresh unless there is a device issue (handled else where)
            freshness = .fresh
            
            if let timeString = ago.truncatedTimeAgoString {
                switch traitCollection.preferredContentSizeCategory {
                case UIContentSizeCategory.extraSmall,
                    UIContentSizeCategory.small,
                    UIContentSizeCategory.medium,
                    UIContentSizeCategory.large:
                    // Use a longer form only for smaller text sizes
                    caption?.attributedText = formattedTimeAgoString(timeString, includeGreaterThan: ago > .hours(1))
                default:
                    caption?.text = timeString
                }
                
                accessibilityLabel = String(format: LocalizedString("Last device communication ran %@ ago", comment: "Accessbility format label describing the time interval since the last device communication date. (1: The localized date components)"), timeString)
            } else {
                caption?.text = ""
                accessibilityLabel = nil
            }
        } else {
            onAgoUpdate?(nil)
            caption?.text = ""
            accessibilityLabel = LocalizedString("Waiting for first run", comment: "Accessibility label describing completion HUD waiting for first run")
        }

        if loopIconClosed {
            accessibilityHint = LocalizedString("Closed loop", comment: "Accessibility hint describing completion HUD for a closed loop")
            accessibilityIdentifier = "loopCompletionHUDLoopStatusClosed"
        } else {
            accessibilityHint = LocalizedString("Open loop", comment: "Accessbility hint describing completion HUD for an open loop")
            accessibilityIdentifier = "loopCompletionHUDLoopStatusOpen"
        }
    }
    
    private func formattedTimeAgoString(_ timeString: String, includeGreaterThan: Bool = false) -> NSAttributedString {
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        // ⚠️ arrow.triangle.2.circlepath is deprecated -- replace with "arrow.trianglehead.2.clockwise.rotate.90" once iOS 17 is dropped as a supported platform.
        let symbol = UIImage(systemName: "arrow.triangle.2.circlepath", withConfiguration: config)
        let tintedSymbol = symbol?.withTintColor(freshnessColor, renderingMode: .alwaysOriginal)
        let attachment = NSTextAttachment()
        attachment.image = tintedSymbol
        attachment.bounds = CGRect(x: 0, y: -2, width: 11, height: 11)
        let imageString = NSAttributedString(attachment: attachment)
        
        let timeAgoString: NSAttributedString
        if includeGreaterThan {
            timeAgoString = NSAttributedString(string: String(format: LocalizedString(" >%@ ago", comment: "Format string describing the time interval since the last completion date, last cgm or last pump communication. (1: The localized date components"), timeString))
        } else {
            timeAgoString = NSAttributedString(string: String(format: LocalizedString(" %@ ago", comment: "Format string describing the time interval since the last completion date, last cgm or last pump communication. (1: The localized date components"), timeString))
        }
        
        let combined = NSMutableAttributedString()
        combined.append(imageString)
        combined.append(timeAgoString)
        
        return combined
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()

        assertTimer()
    }
}
