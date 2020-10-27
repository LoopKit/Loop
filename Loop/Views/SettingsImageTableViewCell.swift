//
//  SettingsImageTableViewCell.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit


class SettingsImageTableViewCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)

        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        setup()
    }

    private func setup() {
        guard let textLabel = textLabel, let imageView = imageView else {
            return
        }
        
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.font = UIFont.preferredFont(forTextStyle: .body)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let parent = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            imageView.topAnchor.constraint(greaterThanOrEqualTo: parent.topAnchor),
            parent.bottomAnchor.constraint(greaterThanOrEqualTo: imageView.bottomAnchor),
            imageView.centerYAnchor.constraint(equalTo: parent.centerYAnchor),
            textLabel.leadingAnchor.constraint(equalToSystemSpacingAfter: imageView.trailingAnchor, multiplier: 2),
            textLabel.topAnchor.constraint(greaterThanOrEqualTo: parent.topAnchor),
            parent.bottomAnchor.constraint(greaterThanOrEqualTo: textLabel.bottomAnchor),
            parent.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor),
            textLabel.centerYAnchor.constraint(equalTo: parent.centerYAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageView?.image = nil
        accessoryType = .none
    }
}
