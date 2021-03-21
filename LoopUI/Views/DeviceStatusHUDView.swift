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
            progressView.tintColor = .systemGray
            // round the edges of the progress view
            progressView.layer.cornerRadius = 2
            progressView.clipsToBounds = true
            progressView.layer.sublayers![1].cornerRadius = 2
            progressView.subviews[1].clipsToBounds = true
        }
    }
    
    @IBOutlet public weak var backgroundView: UIView! {
        didSet {
            backgroundView.backgroundColor = .systemBackground
            backgroundView.layer.cornerRadius = 23
        }
    }
    
    @IBOutlet public weak var statusStackView: UIStackView!
    
    public var lifecycleProgress: DeviceLifecycleProgress? {
        didSet {
            guard let lifecycleProgress = lifecycleProgress else {
                resetProgress()
                return
            }
             
            progressView.isHidden = false
            progressView.progress = Float(lifecycleProgress.percentComplete.clamped(to: 0...1))
            progressView.tintColor = lifecycleProgress.progressState.color
        }
    }
    
    public var adjustViewsForNarrowDisplay: Bool = false {
        didSet {
            if adjustViewsForNarrowDisplay != oldValue {
                NSLayoutConstraint.activate([
                    statusHighlightView.icon.widthAnchor.constraint(equalToConstant: 26),
                    statusHighlightView.icon.heightAnchor.constraint(equalToConstant: 26),
                ])
            } else {
                NSLayoutConstraint.activate([
                    statusHighlightView.icon.widthAnchor.constraint(equalToConstant: 34),
                    statusHighlightView.icon.heightAnchor.constraint(equalToConstant: 34),
                ])
            }
        }
    }
    
    public func resetProgress() {
        progressView.isHidden = true
        progressView.progress = 0
    }
    
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
                               image: statusHighlight.image,
                               color: statusHighlight.color)
    }
    
    public func presentStatusHighlight(withMessage message: String,
                                       image: UIImage?,
                                       color: UIColor)
    {
        statusHighlightView.messageLabel.text = message
        statusHighlightView.messageLabel.tintColor = .label
        statusHighlightView.icon.image = image
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
