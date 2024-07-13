//
//  LoopWidgets.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI

@main
struct LoopWidgets: WidgetBundle {

    @WidgetBundleBuilder
    var body: some Widget {
        SystemStatusWidget()
    }
}
