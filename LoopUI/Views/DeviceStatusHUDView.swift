//
//  DeviceStatusHUDView.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-06-05.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import LoopKitUI

@objc open class DeviceStatusHUDView: BaseHUDView {
    
    public var statusHighlightView: StatusHighlightHUDView! {
        didSet {
            statusHighlightView.isHidden = true
        }
    }
    
    @IBOutlet public weak var progressView: UIProgressView! {
        didSet {
            progressView.isHidden = true
        }
    }
    
    @IBOutlet public weak var backgroundView: UIView! {
        didSet {
            backgroundView.backgroundColor = .systemBackground
            backgroundView.layer.cornerRadius = 23
        }
    }
    
    @IBOutlet public weak var statusStackView: UIStackView!
    
    func setup() {
        if statusHighlightView == nil {
            statusHighlightView = StatusHighlightHUDView(frame: self.frame)
        }
    }
    
    public func presentStatusHighlight(_ statusHighlight: DeviceStatusHighlight?) {
        guard let statusHighlight = statusHighlight else {
            dismissStatusHighlight()
            return
        }
        
        presentStatusHighlight(withMessage: statusHighlight.localizedMessage,
                               icon: statusHighlight.icon,
                               color: statusHighlight.color)
    }
    
    public func presentStatusHighlight(withMessage message: String,
                                       icon: UIImage,
                                       color: UIColor)
    {
        statusHighlightView.messageLabel.text = message
        statusHighlightView.messageLabel.tintColor = .label
        statusHighlightView.icon.image = icon
        statusHighlightView.icon.tintColor = color
        presentStatusHighlight()
    }
    
    func presentStatusHighlight() {
        statusStackView?.addArrangedSubview(statusHighlightView)
        statusHighlightView.isHidden = false
    }
    
    func dismissStatusHighlight() {
        // need to also hide this view, since it will be added back to the stack at some point
        statusHighlightView.isHidden = true
        statusStackView?.removeArrangedSubview(statusHighlightView)
    }
}
