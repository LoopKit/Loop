//
//  HUDRowController.swift
//  WatchApp Extension
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopCore
import LoopKit
import WatchKit

class HUDRowController: NSObject, IdentifiableClass {
    @IBOutlet private var textLabel: WKInterfaceLabel!
    @IBOutlet private var detailTextLabel: WKInterfaceLabel!
    @IBOutlet private var outerGroup: WKInterfaceGroup!
    @IBOutlet private var bottomSeparator: WKInterfaceSeparator!
}

extension HUDRowController {
    func setTitle(_ title: String) {
        textLabel.setText(title.localizedUppercase)
    }

    func setDetail(_ detail: String?) {
        detailTextLabel.setText(detail ?? "—")
    }

    func setContentInset(_ inset: NSDirectionalEdgeInsets) {
        outerGroup.setContentInset(inset.deviceInsets)
    }

    func setIsLastRow(_ isLastRow: Bool) {
        bottomSeparator.setHidden(isLastRow)
    }
}

extension HUDRowController {
    func setActiveInsulin(_ activeInsulin: HKQuantity?) {
        guard let activeInsulin = activeInsulin else {
            setDetail(nil)
            return
        }

        let insulinFormatter: QuantityFormatter = {
            let insulinFormatter = QuantityFormatter()
            insulinFormatter.numberFormatter.minimumFractionDigits = 1
            insulinFormatter.numberFormatter.maximumFractionDigits = 1

            return insulinFormatter
        }()

        setDetail(insulinFormatter.string(from: activeInsulin, for: .internationalUnit()))
    }

    func setActiveCarbohydrates(_ activeCarbohydrates: HKQuantity?) {
        guard let activeCarbohydrates = activeCarbohydrates else {
            setDetail(nil)
            return
        }

        let carbFormatter = QuantityFormatter()
        carbFormatter.numberFormatter.maximumFractionDigits = 0

        setDetail(carbFormatter.string(from: activeCarbohydrates, for: .gram()))
    }

    func setNetTempBasalDose(_ tempBasal: Double?) {
        guard let tempBasal = tempBasal else {
            setDetail(nil)
            return
        }

        let basalFormatter = NumberFormatter()
        basalFormatter.numberStyle = .decimal
        basalFormatter.minimumFractionDigits = 1
        basalFormatter.maximumFractionDigits = 3
        basalFormatter.positivePrefix = basalFormatter.plusSign

        let unit = NSLocalizedString(
            "U/hr",
            comment: "The short unit display string for international units of insulin delivery per hour"
        )

        setDetail(basalFormatter.string(from: tempBasal, unit: unit))
    }

    func setReservoirVolume(_ reservoirVolume: HKQuantity?) {
        guard let reservoirVolume = reservoirVolume else {
            setDetail(nil)
            return
        }

        let insulinFormatter: QuantityFormatter = {
            let insulinFormatter = QuantityFormatter()
            insulinFormatter.unitStyle = .long
            insulinFormatter.numberFormatter.minimumFractionDigits = 0
            insulinFormatter.numberFormatter.maximumFractionDigits = 0

            return insulinFormatter
        }()

        setDetail(insulinFormatter.string(from: reservoirVolume, for: .internationalUnit()))
    }
}


fileprivate extension NSDirectionalEdgeInsets {
    var deviceInsets: UIEdgeInsets {
        let left: CGFloat
        let right: CGFloat

        switch WKInterfaceDevice.current().layoutDirection {
        case .rightToLeft:
            right = leading
            left = trailing
        case .leftToRight:
            fallthrough
        @unknown default:
            left = leading
            right = trailing
        }

        return UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
    }
}
