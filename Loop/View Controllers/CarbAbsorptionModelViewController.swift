//
//  CarbAbsorptionModelViewController.swift
//  Loop
//
//  Created by Ivan Valkou on 06.11.2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import SwiftUI

final class CarbAbsorptionModelViewController: UIHostingController<CarbAbsorptionModelView> {
    init(viewModel: CarbAbsorptionModelView.ViewModel) {
        super.init(rootView: CarbAbsorptionModelView(viewModel: viewModel))
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var onDeinit: (() -> Void)?

    deinit {
        onDeinit?()
    }
}
