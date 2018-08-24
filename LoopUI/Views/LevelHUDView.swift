//
//  LevelHUDView.swift
//  Loop
//
//  Created by Nate Racklyeft on 2/4/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit

public class LevelHUDView: BaseHUDView {

    @IBOutlet private weak var levelMaskView: LevelMaskView!

    override public func awakeFromNib() {
        super.awakeFromNib()

        updateColor()

        accessibilityValue = LocalizedString("Unknown", comment: "Accessibility value for an unknown value")
    }

    public var stateColors: StateColorPalette? {
        didSet {
            updateColor()
        }
    }

    private func updateColor() {
        levelMaskView.tintColor = nil

        switch level {
        case .none:
            tintColor = stateColors?.unknown
        case let x? where x > 0.25:
            tintColor = stateColors?.normal
        case let x? where x > 0.10:
            tintColor = stateColors?.normal
            levelMaskView.tintColor = stateColors?.warning
        default:
            tintColor = stateColors?.error
        }
    }

    internal var level: Double? {
        didSet {
            levelMaskView.value = level ?? 1.0
            updateColor()
        }
    }

}
