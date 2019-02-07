//
//  OverrideSelectionController.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 1/31/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import WatchKit
import LoopKit
import WatchConnectivity


protocol OverrideSelectionControllerDelegate: AnyObject {
    func overrideSelectionController(_ controller: OverrideSelectionController, didSelectPreset preset: TemporaryScheduleOverridePreset)
}


final class OverrideSelectionController: WKInterfaceController, IdentifiableClass {

    @IBOutlet private var table: WKInterfaceTable!

    private let loopManager = ExtensionDelegate.shared().loopManager

    weak var delegate: OverrideSelectionControllerDelegate?
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        delegate = context as? OverrideSelectionControllerDelegate

        let presets = loopManager.settings.overridePresets
        guard !presets.isEmpty else {
            assertionFailure("Instantiating override selection controller without configured presets")
            return
        }

        configureTable(withPresets: presets)
    }

    private func configureTable(withPresets presets: [TemporaryScheduleOverridePreset]) {
        table.setRowTypes([OverridePresetRow.className])
        let presetsPerRow = 2
        let rowCount = Int(ceil(Double(presets.count) / Double(presetsPerRow)))
        table.setNumberOfRows(rowCount, withRowType: OverridePresetRow.className)
        for rowIndex in 0..<rowCount {
            let row = table.rowController(at: rowIndex) as! OverridePresetRow
            let leftPresetIndex = rowIndex * 2
            let leftPreset = presets[leftPresetIndex]

            if rowIndex == rowCount - 1, presets.count % presetsPerRow != 0 {
                // Odd number of presets; last row includes only the left.
                row.presets = (left: leftPreset, right: nil)
            } else {
                let rightPreset = presets[leftPresetIndex + 1]
                row.presets = (left: leftPreset, right: rightPreset)
            }

            row.delegate = self
        }
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didAppear() {
        super.didAppear()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }
}

extension OverrideSelectionController: OverridePresetRowDelegate {
    func overridePresetRowDidTapLeftPresetButton(_ row: OverridePresetRow) {
        guard let preset = row.presets?.left else {
            assertionFailure("Preset row button tapped prior to configuration")
            return
        }
        enabledOverride(fromPreset: preset)
    }

    func overridePresetRowDidTapRightPresetButton(_ row: OverridePresetRow) {
        guard let preset = row.presets?.right else {
            assertionFailure("Preset row button tapped prior to configuration")
            return
        }
        enabledOverride(fromPreset: preset)
    }

    private func enabledOverride(fromPreset preset: TemporaryScheduleOverridePreset) {
        delegate?.overrideSelectionController(self, didSelectPreset: preset)
        dismiss()
    }
}
