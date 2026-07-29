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

    /// The app manager lives on the app delegate because it also serves app-level callbacks
    /// (remote notifications, protected data availability).
    private var loopAppManager: LoopAppManager? {
        (UIApplication.shared.delegate as? AppDelegate)?.loopAppManager
    }

    // MARK: - UIWindowSceneDelegate - Life Cycle

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        log.default(#function)

        guard let windowScene = scene as? UIWindowScene else { return }

        // When the scene is configured with a storyboard, UIKit creates the window and its
        // root view controller and assigns them here. Create one defensively otherwise.
        if window == nil {
            let window = UIWindow(windowScene: windowScene)
            self.window = window
            window.makeKeyAndVisible()
        }

        guard let loopAppManager else { return }

        let launchOptions = (UIApplication.shared.delegate as? AppDelegate)?.launchOptions
        if loopAppManager.isInInitialState {
            loopAppManager.initialize(windowProvider: self, launchOptions: launchOptions)
        }
        if loopAppManager.isLaunchPending {
            loopAppManager.launch()
        }

        if let url = connectionOptions.urlContexts.first?.url {
            _ = loopAppManager.handle(url)
        }

        for userActivity in connectionOptions.userActivities {
            restore(userActivity, with: loopAppManager)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        log.default(#function)

        loopAppManager?.didBecomeActive()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        log.default(#function)

        loopAppManager?.askUserToConfirmLoopReset()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        log.default(#function)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        log.default(#function)
    }

    // MARK: - UIWindowSceneDelegate - Deeplinking

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        _ = loopAppManager?.handle(url)
    }

    // MARK: - UIWindowSceneDelegate - Continuity

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        log.default(#function)

        guard let loopAppManager else { return }
        restore(userActivity, with: loopAppManager)
    }

    // MARK: - Private

    private func restore(_ userActivity: NSUserActivity, with loopAppManager: LoopAppManager) {
        // Mirror UIKit's legacy behavior of invoking `restoreUserActivityState` on each
        // object the app manager hands back through the restoration handler.
        _ = loopAppManager.userActivity(userActivity, restorationHandler: { objects in
            objects?.forEach { $0.restoreUserActivityState(userActivity) }
        })
    }
}
