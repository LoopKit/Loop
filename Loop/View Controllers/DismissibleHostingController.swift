//
//  DismissibleHostingController.swift
//  Loop
//
//  Created by Michael Pangburn on 5/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


class DismissibleHostingController: UIHostingController<AnyView> {
    private var onDisappear: () -> Void = {}

    convenience init<Content: View>(rootView: Content, onDisappear: @escaping () -> Void = {}) {
        // Delay initialization of dismissal closure pushed into SwiftUI Environment until after calling the designated initializer
        var dismiss = {}
        self.init(rootView: AnyView(rootView.environment(\.dismiss, { dismiss() })))
        dismiss = { [weak self] in self?.dismiss(animated: true) }
        self.onDisappear = onDisappear

        isModalInPresentation = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onDisappear()
    }
}
