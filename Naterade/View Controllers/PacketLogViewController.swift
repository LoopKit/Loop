//
//  PacketLogViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/1/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import UIKit
import RileyLinkKit

class PacketLogViewController: UIViewController {

    @IBOutlet weak var logTextView: UITextView!

    private var packetObserver: AnyObject?

    override func viewDidLoad() {
        super.viewDidLoad()

        packetObserver = NSNotificationCenter.defaultCenter().addObserverForName(RileyLinkDeviceDidReceivePacketNotification, object: nil, queue: nil) { (note) -> Void in
            if let packet = note.userInfo?[RileyLinkDevicePacketKey] as? MinimedPacket {
                self.prependLogText(packet.messageData.hexadecimalString)
            }
        }
    }

    deinit {
        if let observer = packetObserver {
            NSNotificationCenter.defaultCenter().removeObserver(observer)
        }
    }

    private func prependLogText(text: String) {
        logTextView.text = "\(text)\n\(logTextView.text)"
    }
}
