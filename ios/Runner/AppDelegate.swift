import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.applicationSupportsShakeToEdit = false // Disable shake to undo
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "PiliNativeGlassTabBar"
    ) else { return }
    registrar.register(
      PiliNativeGlassTabBarFactory(messenger: registrar.messenger()),
      withId: "pili/native_glass_tab_bar"
    )
    registrar.register(
      PiliNativeSegmentedControlFactory(messenger: registrar.messenger()),
      withId: "pili/native_segmented_control"
    )
  }
}
