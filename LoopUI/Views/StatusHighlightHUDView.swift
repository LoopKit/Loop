//
//  StatusHighlightHUDView.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-06-05.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit

public class StatusHighlightHUDView: UIView, NibLoadable {
    
    private var stackView: UIStackView!
    
    @IBOutlet public weak var messageLabel: UILabel!
    
    @IBOutlet public weak var icon: UIImageView! {
        didSet {
            icon.tintColor = tintColor
        }
    }
    
    public enum IconPosition {
        case left
        case right
    }
    
    private var iconPosition: IconPosition = .right {
        didSet {
            stackView.removeArrangedSubview(messageLabel)
            stackView.removeArrangedSubview(icon)
            switch iconPosition {
            case .left:
                stackView.addArrangedSubview(icon)
                stackView.addArrangedSubview(messageLabel)
                messageLabel.textAlignment = .left
            case .right:
                stackView.addArrangedSubview(messageLabel)
                stackView.addArrangedSubview(icon)
                messageLabel.textAlignment = .right
            }
        }
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    func setup() {
        stackView = (StatusHighlightHUDView.nib().instantiate(withOwner: self, options: nil)[0] as! UIStackView)
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
    
    public func setIconPosition(_ iconPosition: IconPosition) {
        if self.iconPosition != iconPosition {
            self.iconPosition = iconPosition
        }
    }
}
