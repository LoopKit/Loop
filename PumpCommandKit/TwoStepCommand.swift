//
//  TwoStepCommand.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/5/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import MinimedKit


protocol TwoStepCommand {
    var firstMessage: PumpMessage { get }
    var firstResponse: MessageType { get }
    var secondMessage: PumpMessage { get }
    var secondResponse: MessageType { get }
}
