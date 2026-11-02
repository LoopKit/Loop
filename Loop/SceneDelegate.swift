//
//  SceneDelegate.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, WindowProvider {

    var window: UIWindow?

    private let log = DiagnosticLog(category: "SceneDelegate")

    private var loopAppManager: LoopAppManager? {
        (UIApplication.shared.delegate as? AppDelegate)?.loopAppManager
    }

    // MARK: - UIWindowSceneDelegate - Connection

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        log.default(#function)


        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        let loopAppManager = appDelegate.loopAppManager

        guard loopAppManager.isInInitialState else {
            return
        }

        window?.addGestureRecognizer(TouchCountingGestureRecognizer { [weak loopAppManager] in
            loopAppManager?.didReceiveTouch()
        })

        loopAppManager.initialize(windowProvider: self, launchOptions: appDelegate.launchOptions)
        loopAppManager.launch()

        if let url = connectionOptions.urlContexts.first?.url {
            _ = loopAppManager.handle(url)
        }
        for userActivity in connectionOptions.userActivities {
            _ = loopAppManager.userActivity(userActivity, restorationHandler: { _ in })
        }
    }

    // MARK: - UIWindowSceneDelegate - Life Cycle

    func sceneDidBecomeActive(_ scene: UIScene) {
        log.default(#function)

        loopAppManager?.didBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        log.default(#function)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        log.default(#function)

        loopAppManager?.willEnterForeground()

        guard let loopAppManager, loopAppManager.isLaunchComplete else {
            return
        }
        loopAppManager.askUserToConfirmLoopReset()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        log.default(#function)

        loopAppManager?.didEnterBackground()
    }

    // MARK: - UIWindowSceneDelegate - Deeplinking

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else {
            return
        }
        _ = loopAppManager?.handle(url)
    }

    // MARK: - UIWindowSceneDelegate - Continuity

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        log.default(#function)

        _ = loopAppManager?.userActivity(userActivity, restorationHandler: { _ in })
    }
}

/// Counts each touch sequence without taking part in gesture recognition.
private final class TouchCountingGestureRecognizer: UIGestureRecognizer {

    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible {
            onTouch()
        }
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}
