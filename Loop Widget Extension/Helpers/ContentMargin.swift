//
//  ContentMargin.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 9/29/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI
import WidgetKit

extension WidgetConfiguration {
    func contentMarginsDisabledIfAvailable() -> some WidgetConfiguration {
        if #available(iOSApplicationExtension 17.0, *) {
            return self.contentMarginsDisabled()
        } else {
            return self
        }
    }
}
