//
//  DismissibleHostingController.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-08-04.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

extension DismissibleHostingController {
    public convenience init(
           rootView: Content,
           dismissalMode: DismissalMode = .modalDismiss,
           isModalInPresentation: Bool = true,
           onDisappear: @escaping () -> Void = {}
    ) {
        self.init(content: rootView,
                  dismissalMode: dismissalMode,
                  isModalInPresentation: isModalInPresentation,
                  onDisappear: onDisappear,
                  guidanceColors: GuidanceColors.default,
                  carbTintColor: .carbTintColor,
                  glucoseTintColor: .glucoseTintColor,
                  insulinTintColor: .insulinTintColor)
    }
}
