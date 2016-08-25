//
//  AuthenticationTableViewCell.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

final class AuthenticationTableViewCell: UITableViewCell, NibLoadable {

    @IBOutlet weak var titleLabel: UILabel!

    @IBOutlet weak var textField: UITextField!

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if selected {
            textField.becomeFirstResponder()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        textField.delegate = nil
    }

}
