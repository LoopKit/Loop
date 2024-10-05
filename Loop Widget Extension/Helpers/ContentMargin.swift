//
//  ContentMargin.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 1/16/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
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
