//
//  HUDView.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/20/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit

public class HUDView: UIView {
    let nibName:String = "HUDStackView"
    public var view: HUDStackView!

    func setup() {
        let bundle = Bundle(for: type(of: self))
        let nib = UINib(nibName: self.nibName, bundle: bundle)
        let instances = nib.instantiate(withOwner: self, options: nil)
        self.view = instances[0] as! HUDStackView
        self.view.frame = bounds
        self.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(self.view)
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
