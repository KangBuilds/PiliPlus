import AVFoundation
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nowPlayingChannel: FlutterMethodChannel?
  private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
  private var audioSessionState = NowPlayingAudioSessionState()
  private var artworkURL: String?
  private var artworkTask: URLSessionDataTask?
  private var artwork: MPMediaItemArtwork?

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
      forPlugin: "PiliPlusNative"
    ) else { return }
    configureNowPlaying(messenger: registrar.messenger())
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
        result(self?.updateNowPlaying(call.arguments as? [String: Any]))
      case "NowPlaying.Clear":
        self?.clearNowPlaying()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nowPlayingChannel = channel
    UIApplication.shared.beginReceivingRemoteControlEvents()

    for (command, target) in remoteCommandTargets {
      command.removeTarget(target)
    }
    remoteCommandTargets.removeAll()

    let commands = MPRemoteCommandCenter.shared()
    addTarget(commands.playCommand, method: "NowPlaying.Play")
    addTarget(commands.pauseCommand, method: "NowPlaying.Pause")
    addTarget(commands.togglePlayPauseCommand, method: "NowPlaying.Toggle")
    addTarget(commands.nextTrackCommand, method: "NowPlaying.Next")
    addTarget(commands.previousTrackCommand, method: "NowPlaying.Previous")
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

  private func updateNowPlaying(_ arguments: [String: Any]?) -> FlutterError? {
    guard let arguments, arguments["active"] as? Bool == true else {
      clearNowPlaying()
      return nil
    }

    let playing = arguments["playing"] as? Bool == true
    let rate = arguments["rate"] as? Double ?? 1
    let audioSession = AVAudioSession.sharedInstance()
    var sessionError: FlutterError?
    do {
      try audioSessionState.update(
        playing: playing,
        needsConfiguration: audioSession.category != .playback
          || audioSession.categoryOptions.contains(.mixWithOthers),
        configure: {
          try audioSession.setCategory(.playback, mode: audioSession.mode, options: [])
        },
        activate: { try audioSession.setActive(true) }
      )
    } catch {
      let error = error as NSError
      sessionError = FlutterError(
        code: "audio_session_error",
        message: error.localizedDescription,
        details: ["domain": error.domain, "code": error.code]
      )
    }
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = !playing
    commands.pauseCommand.isEnabled = playing
    commands.togglePlayPauseCommand.isEnabled = true
    commands.changePlaybackPositionCommand.isEnabled = true
    commands.nextTrackCommand.isEnabled = arguments["canSkipNext"] as? Bool == true
    commands.previousTrackCommand.isEnabled = arguments["canSkipPrevious"] as? Bool == true
    loadArtwork(arguments["artwork"] as? String)

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: arguments["title"] as? String ?? "PiliPlus",
      MPMediaItemPropertyPlaybackDuration: arguments["duration"] as? Double ?? 0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: arguments["position"] as? Double ?? 0,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? rate : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
      MPNowPlayingInfoPropertyMediaType: arguments["audioOnly"] as? Bool == true
        ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
    ]
    info[MPMediaItemPropertyArtwork] = artwork
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    return sessionError
  }

  private func loadArtwork(_ value: String?) {
    let value = value?.replacingOccurrences(of: "http://", with: "https://")
    guard artworkURL != value else { return }
    artworkTask?.cancel()
    artworkURL = value
    artwork = nil
    guard let value, !value.isEmpty, let url = URL(string: value) else { return }

    artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.artworkURL == value else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.artwork = artwork
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      }
    }
    artworkTask?.resume()
  }

  private func clearNowPlaying() {
    audioSessionState = NowPlayingAudioSessionState()
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = false
    commands.pauseCommand.isEnabled = false
    commands.togglePlayPauseCommand.isEnabled = false
    commands.changePlaybackPositionCommand.isEnabled = false
    commands.nextTrackCommand.isEnabled = false
    commands.previousTrackCommand.isEnabled = false
    artworkTask?.cancel()
    artworkTask = nil
    artworkURL = nil
    artwork = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
  }
}
