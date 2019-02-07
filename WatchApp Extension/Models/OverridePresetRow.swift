//
//  OverridePresetRow.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 1/31/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import WatchKit
import LoopKit


protocol OverridePresetRowDelegate: AnyObject {
    func overridePresetRowDidTapLeftPresetButton(_ row: OverridePresetRow)
    func overridePresetRowDidTapRightPresetButton(_ row: OverridePresetRow)
}

final class OverridePresetRow: NSObject, IdentifiableClass {
    @IBOutlet private var leftPresetButton: WKInterfaceButton!
    @IBOutlet private var rightPresetButton: WKInterfaceButton!

    var presets: (left: TemporaryScheduleOverridePreset, right: TemporaryScheduleOverridePreset?)? {
        didSet {
            leftPresetButton.setTitle(presets?.left.symbol)
            if let right = presets?.right {
                rightPresetButton.setTitle(right.symbol)
            } else {
                rightPresetButton.setHidden(true)
            }
        }
    }

    weak var delegate: OverridePresetRowDelegate?

    @IBAction func leftPresetButtonTapped() {
        delegate?.overridePresetRowDidTapLeftPresetButton(self)
    }

    @IBAction func rightPresetButtonTapped() {
        delegate?.overridePresetRowDidTapRightPresetButton(self)
    }
}
