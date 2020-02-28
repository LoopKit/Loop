//
//  OverrideBadgeView.swift
//  Loop
//
//  Created by Michael Pangburn on 2/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit


@IBDesignable
final class OverrideBadgeView: UIView {
    private let emojiLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24)
        return label
    }()

    var emoji: String? {
        get { emojiLabel.text }
        set {
            emojiLabel.text = newValue
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.glucoseTintColor.withAlphaComponent(0.7)
        addSubview(emojiLabel)
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(frame.width, frame.height) / 2
    }

    override var intrinsicContentSize: CGSize {
        var size = emojiLabel.intrinsicContentSize
        let borderMargin: CGFloat = 3
        size.width += 2 * borderMargin
        size.height += 2 * borderMargin
        return size
    }

    override func prepareForInterfaceBuilder() {
        invalidateIntrinsicContentSize()
    }
}
