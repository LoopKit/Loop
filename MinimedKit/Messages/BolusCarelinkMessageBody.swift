//
//  BolusCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class BolusCarelinkMessageBody: CarelinkLongMessageBody {

    public convenience init(units: Double, strokesPerUnit: Int = 40) {

        let length = strokesPerUnit <= 10 ? 1 : 2
        let strokes: Int

        // 40-stroke pumps only support 1/20 increments when programming < 1 unit
        if units > 1 && strokesPerUnit >= 40 {
            strokes = Int(units * Double(strokesPerUnit / 2)) * 2
        } else {
            strokes = Int(units * Double(strokesPerUnit))
        }

        let data = NSData(hexadecimalString: String(format: "%02x%0\(2 * length)x", length, strokes))!

        self.init(rxData: data)!
    }

}