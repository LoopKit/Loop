//
//  ButtonTableViewCell.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


final class ButtonTableViewCell: UITableViewCell, NibLoadable {

    @IBOutlet weak var button: UIButton!

    override func prepareForReuse() {
        super.prepareForReuse()

        button.removeTarget(nil, action: nil, forControlEvents: .TouchUpInside)
    }
}
