//
//  SceneDelegate.swift
//  Loop
//
//  Scene-based lifecycle support for iOS 27.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, WindowProvider {

    var window: UIWindow?

    private var loopAppManager: LoopAppManager {
        (UIApplication.shared.delegate as! AppDelegate).loopAppManager
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)

        guard let rootViewController = storyboard.instantiateInitialViewController() else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = rootViewController

        self.window = window

        window.makeKeyAndVisible()

        loopAppManager.initialize(
            windowProvider: self,
            launchOptions: nil
        )

        loopAppManager.launch()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        loopAppManager.didBecomeActive()
    }
}
