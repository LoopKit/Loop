//
//  CarbAndBolusFlowController.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import WatchKit
import SwiftUI
import HealthKit
import LoopCore
import LoopKit


final class CarbAndBolusFlowController: WKHostingController<CarbAndBolusFlow>, IdentifiableClass {
    private lazy var viewModel = {
        CarbAndBolusFlowViewModel(
            configuration: configuration,
            dismiss: { [weak self] in
                guard let self = self else { return }
                self.willDeactivateObserver = nil
                self.dismiss()
            }
        )
    }()

    private var configuration: CarbAndBolusFlow.Configuration = .carbEntry

    override var body: CarbAndBolusFlow {
        CarbAndBolusFlow(viewModel: viewModel)
    }

    private var willDeactivateObserver: AnyObject? {
        didSet {
            if let oldValue = oldValue {
                NotificationCenter.default.removeObserver(oldValue)
            }
        }
    }

    override func awake(withContext context: Any?) {
        if let configuration = context as? CarbAndBolusFlow.Configuration {
            self.configuration = configuration
        }
    }

    override func didAppear() {
        super.didAppear()

        updateNewCarbEntryUserActivity()

        // If the screen turns off, the screen should be dismissed for safety reasons
        willDeactivateObserver = NotificationCenter.default.addObserver(forName: ExtensionDelegate.willResignActiveNotification, object: ExtensionDelegate.shared(), queue: nil, using: { [weak self] (_) in
            if let self = self {
                WKInterfaceDevice.current().play(.failure)
                self.dismiss()
            }
        })
    }

    override func didDeactivate() {
        super.didDeactivate()

        willDeactivateObserver = nil
    }
}

extension CarbAndBolusFlowController: NSUserActivityDelegate {
    func updateNewCarbEntryUserActivity() {
        update(.forDidAddCarbEntryOnWatch())
    }
}
