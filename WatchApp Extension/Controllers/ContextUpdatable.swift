//
//  ContextUpdatable.swift
//  Loop
//
//  Created by Nate Racklyeft on 9/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


protocol ContextUpdatable {
    func update(with context: WatchContext?)
}
