import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        let contentView = MainCameraView()
            .preferredColorScheme(.dark)
            .statusBar(hidden: true)
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: contentView)
        window.overrideUserInterfaceStyle = .dark
        self.window = window
        window.makeKeyAndVisible()
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {}
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        NotificationCenter.default.post(name: .cameraShouldResume, object: nil)
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        NotificationCenter.default.post(name: .cameraShouldPause, object: nil)
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {}
    
    func sceneDidEnterBackground(_ scene: UIScene) {}
}

extension Notification.Name {
    static let cameraShouldResume = Notification.Name("cameraShouldResume")
    static let cameraShouldPause = Notification.Name("cameraShouldPause")
    static let captureModeDidChange = Notification.Name("captureModeDidChange")
    static let captureDidComplete = Notification.Name("captureDidComplete")
}
