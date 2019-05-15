//
//  TitleSubtitleTableViewCell.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class TitleSubtitleTableViewCell: UITableViewCell {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var subtitleLabel: UILabel! {
        didSet {
            subtitleLabel.textColor = UIColor.secondaryLabelColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        gradient.frame = bounds
    }

    private lazy var gradient = CAGradientLayer()

    override func awakeFromNib() {
        super.awakeFromNib()

        gradient.frame = bounds
        
        //DarkMode
        NotificationCenter.default.addObserver(self, selector: #selector(darkModeEnabled(_:)), name: .darkModeEnabled, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(darkModeDisabled(_:)), name: .darkModeDisabled, object: nil)

        UserDefaults.standard.bool(forKey: "DarkModeEnabled") ?
            NotificationCenter.default.post(name: .darkModeEnabled, object: nil) :
            NotificationCenter.default.post(name: .darkModeDisabled, object: nil)
        //DarkMode
        
        backgroundView?.layer.insertSublayer(gradient, at: 0)
    }

    //DarkMode
    @objc func darkModeEnabled(_ notification: Notification) {
        gradient.colors = [UIColor.black.lighter(by: 25)!.cgColor, UIColor.black.lighter(by: 25)!.cgColor]
    }
    
    @objc func darkModeDisabled(_ notification: Notification) {
        gradient.colors = [UIColor.white.cgColor, UIColor.cellBackgroundColor.cgColor]
    }
    //DarkMode
}
