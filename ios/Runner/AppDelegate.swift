import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nowPlayingChannel: FlutterMethodChannel?
  private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []

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
    configureNowPlaying(messenger: registrar.messenger())
    registrar.register(
      PiliNativeGlassTabBarFactory(messenger: registrar.messenger()),
      withId: "pili/native_glass_tab_bar"
    )
    registrar.register(
      PiliNativeSegmentedControlFactory(messenger: registrar.messenger()),
      withId: "pili/native_segmented_control"
    )
  }

  private func configureNowPlaying(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.PiliPlus/now_playing",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "NowPlaying.Update":
        self?.updateNowPlaying(call.arguments as? [String: Any])
        result(nil)
      case "NowPlaying.Clear":
        self?.clearNowPlaying()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nowPlayingChannel = channel

    for (command, target) in remoteCommandTargets {
      command.removeTarget(target)
    }
    remoteCommandTargets.removeAll()

    let commands = MPRemoteCommandCenter.shared()
    addTarget(commands.playCommand, method: "NowPlaying.Play")
    addTarget(commands.pauseCommand, method: "NowPlaying.Pause")
    addTarget(commands.togglePlayPauseCommand, method: "NowPlaying.Toggle")
    addTarget(commands.changePlaybackPositionCommand) { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.invokeNowPlaying(
        "NowPlaying.Seek",
        arguments: ["position": event.positionTime]
      )
      return .success
    }
  }

  private func addTarget(_ command: MPRemoteCommand, method: String) {
    addTarget(command) { [weak self] _ in
      self?.invokeNowPlaying(method)
      return .success
    }
  }

  private func addTarget(
    _ command: MPRemoteCommand,
    handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
  ) {
    let target = command.addTarget(handler: handler)
    remoteCommandTargets.append((command, target))
  }

  private func invokeNowPlaying(_ method: String, arguments: Any? = nil) {
    DispatchQueue.main.async { [weak self] in
      self?.nowPlayingChannel?.invokeMethod(method, arguments: arguments)
    }
  }

  private func updateNowPlaying(_ arguments: [String: Any]?) {
    guard let arguments, arguments["active"] as? Bool == true else {
      clearNowPlaying()
      return
    }

    let playing = arguments["playing"] as? Bool == true
    let rate = arguments["rate"] as? Double ?? 1
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = !playing
    commands.pauseCommand.isEnabled = playing
    commands.togglePlayPauseCommand.isEnabled = true
    commands.changePlaybackPositionCommand.isEnabled = true

    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: arguments["title"] as? String ?? "PiliPlus",
      MPMediaItemPropertyPlaybackDuration: arguments["duration"] as? Double ?? 0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: arguments["position"] as? Double ?? 0,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? rate : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
  }

  private func clearNowPlaying() {
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = false
    commands.pauseCommand.isEnabled = false
    commands.togglePlayPauseCommand.isEnabled = false
    commands.changePlaybackPositionCommand.isEnabled = false
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }
}
