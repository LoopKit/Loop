//
//  Debug.swift
//  Loop
//
//  Created by Michael Pangburn on 3/5/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

func assertingDebugOnly(file: StaticString = #file, line: UInt = #line, _ doIt: () -> Void) {
    #if DEBUG || IOS_SIMULATOR
    doIt()
    #else
    fatalError("\(file):\(line) should never be invoked in release builds", file: file, line: line)
    #endif
}
