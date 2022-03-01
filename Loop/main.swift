//
//  main.swift
//  Loop
//
//  Created by Rick Pasetto on 10/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit

#if FORCE_ENGLISH
UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
UserDefaults.standard.synchronize()
#endif

UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    NSStringFromClass(UIApplication.self),
    NSStringFromClass(AppDelegate.self)
)
