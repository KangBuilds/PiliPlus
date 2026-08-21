import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillEnterForeground(_ scene: UIScene) {
    if let windowScene = scene as? UIWindowScene,
      let orientations = window?.rootViewController?.supportedInterfaceOrientations
    {
      windowScene.requestGeometryUpdate(
        .iOS(interfaceOrientations: orientations)
      )
      window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
    super.sceneWillEnterForeground(scene)
  }

  @available(iOS 26.0, *)
  override func preferredWindowingControlStyle(
    for windowScene: UIWindowScene
  ) -> UIWindowScene.WindowingControlStyle {
    return .minimal
  }
}
