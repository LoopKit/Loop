//
//  CommandResponseViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class CommandResponseViewController: UIViewController {
    typealias Command = (completionHandler: (responseText: String) -> Void) -> String

    init(command: Command) {
        self.command = command

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let command: Command

    private lazy var textView = UITextView()

    override func loadView() {
        self.view = textView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        textView.font = UIFont(name: "Menlo-Regular", size: 14)
        textView.text = command { [weak self] (responseText) -> Void in
            self?.textView.text = responseText
        }
    }

}
