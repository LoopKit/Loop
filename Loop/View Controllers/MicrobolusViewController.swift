//
//  MicrobolusViewController.swift
//  Loop
//
//  Created by Ivan Valkou on 01.11.2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import SwiftUI

final class MicrobolusViewController: UIHostingController<MicrobolusView> {
    init(viewModel: MicrobolusView.ViewModel) {
        super.init(rootView: MicrobolusView(viewModel: viewModel))
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var onDeinit: (() -> Void)?

    deinit {
        onDeinit?()
    }
}
