#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

public class MediaKitVideoPlugin: NSObject, FlutterPlugin {
  private static let CHANNEL_NAME = "com.alexmercerind/media_kit_video"

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if canImport(Flutter)
      let binaryMessenger = registrar.messenger()
      let registry = registrar.textures()
      let utils: UtilsProtocol? = nil
    #elseif canImport(FlutterMacOS)
      let binaryMessenger = registrar.messenger
      let registry = registrar.textures
      let utils: UtilsProtocol? = Utils(registrar)
    #endif

    let channel = FlutterMethodChannel(
      name: CHANNEL_NAME,
      binaryMessenger: binaryMessenger
    )
    let instance = MediaKitVideoPlugin(
      registry: registry,
      channel: channel,
      utils: utils
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private let channel: FlutterMethodChannel
  private let videoOutputManager: VideoOutputManager
  private let utils: UtilsProtocol?
  #if os(iOS)
    private let pictureInPicture: PictureInPictureController
  #endif

  init(
    registry: FlutterTextureRegistry,
    channel: FlutterMethodChannel,
    utils: UtilsProtocol?
  ) {
    self.channel = channel
    #if os(iOS)
      let pictureInPicture = PictureInPictureController()
      self.pictureInPicture = pictureInPicture
      videoOutputManager = VideoOutputManager(
        registry: registry,
        pixelBufferUpdateCallback: { [weak pictureInPicture] handle, pixelBuffer in
          pictureInPicture?.enqueue(handle: handle, pixelBuffer: pixelBuffer)
        }
      )
      pictureInPicture.onSetPlaying = { handle, playing in
        channel.invokeMethod(
          "PictureInPicture.SetPlaying",
          arguments: ["handle": handle, "playing": playing]
        )
      }
      pictureInPicture.onSeek = { handle, position in
        channel.invokeMethod(
          "PictureInPicture.Seek",
          arguments: ["handle": handle, "position": position]
        )
      }
    #else
      videoOutputManager = VideoOutputManager(registry: registry)
    #endif
    self.utils = utils
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "VideoOutputManager.Create":
      handleCreateMethodCall(call.arguments, result)
    case "VideoOutputManager.SetSize":
      handleSetSizeMethodCall(call.arguments, result)
    case "VideoOutputManager.Dispose":
      handleDisposeMethodCall(call.arguments, result)
    case "Utils.EnterNativeFullscreen":
      handleEnterNativeFullscreenMethodCall(call.arguments, result)
    case "Utils.ExitNativeFullscreen":
      handleExitNativeFullscreenMethodCall(call.arguments, result)
    #if os(iOS)
      case "PictureInPicture.Start":
        handlePictureInPictureStart(call.arguments, result)
      case "PictureInPicture.Update":
        handlePictureInPictureUpdate(call.arguments, result)
      case "PictureInPicture.Stop":
        pictureInPicture.stop()
        result(nil)
    #endif
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleCreateMethodCall(
    _ arguments: Any?,
    _ result: FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let handle: Int64? = Int64(handleStr)
    let configDict = args?["configuration"] as! [String: Any]
    let configuration = VideoOutputConfiguration.fromDict(configDict)

    assert(handle != nil, "handle must be an Int64")

    videoOutputManager.create(
      handle: handle!,
      configuration: configuration,
      textureUpdateCallback: { (_ textureId: Int64, _ size: CGSize) in
        self.channel.invokeMethod(
          "VideoOutput.Resize",
          arguments: [
            "handle": handle!,
            "id": textureId,
            "rect": [
              "top": 0,
              "left": 0,
              "width": size.width,
              "height": size.height,
            ],
          ] as [String: Any]
        )
      }
    )

    result(nil)
  }

  private func handleSetSizeMethodCall(
    _ arguments: Any?,
    _ result: FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let widthStr = args?["width"] as! String
    let heightStr = args?["height"] as! String

    let handle: Int64? = Int64(handleStr)
    let width: Int64? = Int64(widthStr)
    let height: Int64? = Int64(heightStr)

    assert(handle != nil, "handle must be an Int64")

    self.videoOutputManager.setSize(
      handle: handle!,
      width: width,
      height: height
    )

    result(nil)
  }

  private func handleDisposeMethodCall(
    _ arguments: Any?,
    _ result: FlutterResult
  ) {
    let args = arguments as? [String: Any]
    let handleStr = args?["handle"] as! String
    let handle: Int64? = Int64(handleStr)

    assert(handle != nil, "handle must be an Int64")

    videoOutputManager.destroy(
      handle: handle!
    )

    result(nil)
  }

  private func handleEnterNativeFullscreenMethodCall(
    _: Any?,
    _ result: FlutterResult
  ) {
    if utils == nil {
      return result(FlutterMethodNotImplemented)
    }

    utils?.enterNativeFullscreen()
    result(nil)
  }

  private func handleExitNativeFullscreenMethodCall(
    _: Any?,
    _ result: FlutterResult
  ) {
    if utils == nil {
      return result(FlutterMethodNotImplemented)
    }

    utils?.exitNativeFullscreen()
    result(nil)
  }

  #if os(iOS)
    private func handlePictureInPictureStart(
      _ arguments: Any?,
      _ result: FlutterResult
    ) {
      let args = arguments as? [String: Any]
      guard let handleString = args?["handle"] as? String,
            let handle = Int64(handleString) else {
        return result(false)
      }
      result(
        pictureInPicture.start(
          handle: handle,
          position: (args?["position"] as? NSNumber)?.doubleValue ?? 0,
          duration: (args?["duration"] as? NSNumber)?.doubleValue ?? 0,
          playing: (args?["playing"] as? Bool) ?? false
        )
      )
    }

    private func handlePictureInPictureUpdate(
      _ arguments: Any?,
      _ result: FlutterResult
    ) {
      let args = arguments as? [String: Any]
      pictureInPicture.update(
        position: (args?["position"] as? NSNumber)?.doubleValue ?? 0,
        duration: (args?["duration"] as? NSNumber)?.doubleValue ?? 0,
        playing: (args?["playing"] as? Bool) ?? false
      )
      result(pictureInPicture.isActiveOrPending)
    }
  #endif
}
