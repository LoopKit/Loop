//
//  ExplicitlyDismissibleModal.swift
//  Loop
//
//  Created by Michael Pangburn on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import SwiftUI


class ExplicitlyDismissibleModal: UINavigationController {
    private var onDisappear: (() -> Void)?

    convenience init<V: View>(rootView: V, onDisappear: (() -> Void)? = nil) {
        // Delay initialization of dismissal closure pushed into SwiftUI Environment until after calling the designated initializer
        var dismiss = {}
        let hostingController = UIHostingController(rootView: rootView.environment(\.dismiss, { dismiss() }))
        self.init(rootViewController: hostingController)
        dismiss = { [weak self] in self?.dismiss(animated: true) }

        hostingController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        hostingController.isModalInPresentation = true

        self.onDisappear = onDisappear
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onDisappear?()
    }

    @objc private func cancel() {
        self.dismiss(animated: true)
    }
}
