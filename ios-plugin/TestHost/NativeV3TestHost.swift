import UIKit

// Hosted XCTest retains simulator services, including the native OSLog oracle.
@main
final class NativeV3TestHostAppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: "NativeV3Tests", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = NativeV3TestHostSceneDelegate.self
    return configuration
  }
}

final class NativeV3TestHostSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = UIViewController()
    self.window = window
    window.makeKeyAndVisible()
  }
}
