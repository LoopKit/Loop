//
//  StatusBarHUDView.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-06-05.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKitUI

public class StatusBarHUDView: UIView, NibLoadable {
    
    @IBOutlet public weak var cgmStatusHUD: CGMStatusHUDView!
    
    @IBOutlet public weak var loopCompletionHUD: LoopCompletionHUDView!
    
    @IBOutlet public weak var pumpStatusHUD: PumpStatusHUDView!
        
    public var containerView: UIStackView!
    
    public var adjustViewsForNarrowDisplay: Bool = false {
        didSet {
            if adjustViewsForNarrowDisplay != oldValue {
                cgmStatusHUD.adjustViewsForNarrowDisplay = adjustViewsForNarrowDisplay
                pumpStatusHUD.adjustViewsForNarrowDisplay = adjustViewsForNarrowDisplay
                containerView.spacing = adjustViewsForNarrowDisplay ? 8.0 : 16.0
            }
        }
    }

    override public var bounds: CGRect {
        didSet {
            // need to adjust for narrow display. The labels in the status bar need more space when the bounds width is less than 350 points.
            adjustViewsForNarrowDisplay = bounds.width < 350
        }
    }
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    func setup() {
        containerView = (StatusBarHUDView.nib().instantiate(withOwner: self, options: nil)[0] as! UIStackView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(containerView)

        // Use AutoLayout to have the stack view fill its entire container.
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: widthAnchor),
            containerView.heightAnchor.constraint(equalTo: heightAnchor),
        ])
        
        self.backgroundColor = UIColor.secondarySystemBackground
    }
        
    public func removePumpManagerProvidedView() {
        pumpStatusHUD.removePumpManagerProvidedHUD()
    }
    
    public func addPumpManagerProvidedHUDView(_ pumpManagerProvidedHUD: BaseHUDView) {
        pumpStatusHUD.addPumpManagerProvidedHUDView(pumpManagerProvidedHUD)
    }
}
