//
//  ReservoirVolumeHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class ReservoirVolumeHUDView: HUDView {

    @IBOutlet private var imageView: UIImageView!

    private lazy var numberFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .DecimalStyle
        formatter.minimumFractionDigits = 1

        return formatter
    }()

    var reservoirVolume: Double? {
        didSet {
            if let volume = reservoirVolume, units = numberFormatter.stringFromNumber(volume) {
                caption.text = "\(units) U"
            } else {
                caption.text = nil
            }
        }
    }

    var reservoirLevel: Double? {
        didSet {
            imageView.image = UIImage.reservoirHUDImageWithLevel(reservoirLevel)
        }
    }

}
