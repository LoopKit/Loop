//
//  WalshInsulinModel.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import InsulinKit


extension WalshInsulinModel: RawRepresentable {
    public typealias RawValue = [String: Any]

    public init?(rawValue: RawValue) {
        guard let duration = rawValue["actionDuration"] as? TimeInterval else {
            return nil
        }

        self.init(actionDuration: duration)
    }

    public var rawValue: [String : Any] {
        return ["actionDuration": self.actionDuration]
    }
}


// MARK: - Localization
extension WalshInsulinModel {
    var title: String {
        return NSLocalizedString("Walsh", comment: "Title of insulin model setting")
    }

    var subtitle: String {
        return NSLocalizedString("The legacy model used by Loop, allowing customization of action duration.", comment: "Subtitle description of Walsh insulin model setting")
    }
}
