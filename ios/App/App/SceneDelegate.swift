import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var privacyLock: PrivacyLock?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        // Contrôleur Physalis : enregistre le plugin local PhysalisAuth.
        window.rootViewController = PhysalisBridgeViewController()
        window.makeKeyAndVisible()
        self.window = window

        let lock = PrivacyLock(window: window)
        lock.lockAtLaunch()
        privacyLock = lock

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        privacyLock?.sceneDidBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        privacyLock?.sceneWillResignActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        privacyLock?.sceneDidEnterBackground()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}
