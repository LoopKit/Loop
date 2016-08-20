//
//  ValidatingIndicatorView.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

private let Margin: CGFloat = 8


final class ValidatingIndicatorView: UIView {

    let indicatorView = UIActivityIndicatorView(activityIndicatorStyle: .Gray)

    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.preferredFontForTextStyle(UIFontTextStyleHeadline)
        label.text = NSLocalizedString("Verifying", comment: "Label indicating validation is occurring")
        label.sizeToFit()

        addSubview(indicatorView)
        addSubview(label)

        self.frame.size = intrinsicContentSize()

        setNeedsLayout()

        indicatorView.startAnimating()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Center the label in the bounds so it appears aligned, then let the indicator view hang from the left side
        label.frame = bounds
        indicatorView.center.y = bounds.midY
        indicatorView.frame.origin.x = -indicatorView.frame.size.width - Margin
    }

    override func intrinsicContentSize() -> CGSize {
        return label.intrinsicContentSize()
    }
}
