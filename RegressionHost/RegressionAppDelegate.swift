import UIKit

// Isolated test host supplies UIApplication event delivery and windows without
// starting ARKit, camera permissions, network updates or the production App.
@main
final class RegressionAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .black
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
