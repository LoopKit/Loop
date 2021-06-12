//
//  LoopUIColorPalette+Default.swift
//  LoopUI
//
//  Created by Darin Krauss on 1/14/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import LoopKitUI

extension LoopUIColorPalette {
    public static var `default`: LoopUIColorPalette {
        return LoopUIColorPalette(guidanceColors: .default,
                                  carbTintColor: .carbTintColor,
                                  glucoseTintColor: .glucoseTintColor,
                                  insulinTintColor: .insulinTintColor,
                                  loopStatusColorPalette: .loopStatus,
                                  chartColorPalette: .primary)
    }
}
