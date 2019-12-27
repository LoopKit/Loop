//
//  UIActivityIndicatorView.swift
//  LoopKitUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit


extension UIActivityIndicatorView.Style {
    static var `default`: UIActivityIndicatorView.Style {
        if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
            return .medium
        } else {
            return .gray
        }
    }
}
