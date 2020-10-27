//
//  HUDView.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/20/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKitUI

public class HUDView: UIView, NibLoadable {
    @IBOutlet public weak var loopCompletionHUD: LoopCompletionHUDView!
    @IBOutlet public weak var glucoseHUD: GlucoseHUDView!
    @IBOutlet public weak var basalRateHUD: BasalRateHUDView!
    
    private var stackView: UIStackView!

    func setup() {
        stackView = (HUDView.nib().instantiate(withOwner: self, options: nil)[0] as! UIStackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stackView)

        // Use AutoLayout to have the stack view fill its entire container.
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.widthAnchor.constraint(equalTo: widthAnchor),
            stackView.heightAnchor.constraint(equalTo: heightAnchor),
        ])
    }
    
    public func removePumpManagerProvidedViews() {
        let standardViews: [UIView] = [loopCompletionHUD, glucoseHUD, basalRateHUD]
        let pumpManagerViews = stackView.subviews.filter { !standardViews.contains($0) }
        for view in pumpManagerViews {
            view.removeFromSuperview()
        }
    }
    
    public func addHUDView(_ viewToAdd: BaseHUDView) {
        let insertIndex = stackView.arrangedSubviews.firstIndex { (view) -> Bool in
            guard let hudView = view as? BaseHUDView else {
                return false
            }
            return viewToAdd.orderPriority <= hudView.orderPriority
        }

        stackView.insertArrangedSubview(viewToAdd, at: insertIndex ?? stackView.arrangedSubviews.count)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
}
