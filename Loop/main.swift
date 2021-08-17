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
#else
UserDefaults.standard.set(nil, forKey: "AppleLanguages")
#endif
UserDefaults.standard.synchronize()

UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    NSStringFromClass(UIApplication.self),
    NSStringFromClass(AppDelegate.self)
)
