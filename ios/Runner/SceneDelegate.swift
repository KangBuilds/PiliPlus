import AVFoundation
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillEnterForeground(_ scene: UIScene) {
    if let layer = window?.layer {
      flushVideoLayers(in: layer)
    }
    super.sceneWillEnterForeground(scene)
  }

  private func flushVideoLayers(in layer: CALayer) {
    (layer as? AVSampleBufferDisplayLayer)?.flush()
    layer.sublayers?.forEach(flushVideoLayers)
  }

  @available(iOS 26.0, *)
  override func preferredWindowingControlStyle(
    for windowScene: UIWindowScene
  ) -> UIWindowScene.WindowingControlStyle {
    return .minimal
  }
}
