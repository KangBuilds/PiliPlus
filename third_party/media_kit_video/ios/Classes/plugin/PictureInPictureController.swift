import AVKit
import CoreMedia
import UIKit

final class PictureInPictureController: NSObject {
  var onSetPlaying: ((Int64, Bool) -> Void)?
  var onSeek: ((Int64, Double) -> Void)?

  private let displayLayer = AVSampleBufferDisplayLayer()
  private let hostClock = CMClockGetHostTimeClock()
  private var controller: AVPictureInPictureController?
  private var possibleObservation: NSKeyValueObservation?
  private var hostView: UIView?
  private var formatDescription: CMVideoFormatDescription?
  private var formatSize = CGSize.zero
  private var handle: Int64?
  private var duration = 0.0
  private var position = 0.0
  private var playing = false
  private var pendingStart = false
  private var loggedFirstFrame = false

  override init() {
    super.init()
    displayLayer.videoGravity = .resizeAspect
    var timebase: CMTimebase?
    if CMTimebaseCreateWithSourceClock(
      allocator: kCFAllocatorDefault,
      sourceClock: hostClock,
      timebaseOut: &timebase
    ) == noErr, let timebase {
      displayLayer.controlTimebase = timebase
      CMTimebaseSetTime(timebase, time: CMClockGetTime(hostClock))
      CMTimebaseSetRate(timebase, rate: 1)
    }
  }

  private func setupController() {
    guard controller == nil else { return }
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    possibleObservation = controller.observe(
      \.isPictureInPicturePossible,
      options: [.initial, .new]
    ) { [weak self] controller, _ in
      NSLog("PiliPlus PiP: possible=\(controller.isPictureInPicturePossible)")
      if controller.isPictureInPicturePossible {
        self?.startIfPossible()
      }
    }
    self.controller = controller
  }

  private func attachDisplayLayer() -> Bool {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .sorted {
        $0.activationState == .foregroundActive
          && $1.activationState != .foregroundActive
      }
    var windows = scenes.flatMap(\.windows)
    if let appDelegateWindow = UIApplication.shared.delegate?.window ?? nil,
       !windows.contains(where: { $0 === appDelegateWindow }) {
      windows.append(appDelegateWindow)
    }
    let window = windows.first(where: \.isKeyWindow)
      ?? windows.first {
        !$0.isHidden && $0.alpha > 0 && $0.windowLevel == .normal
          && $0.rootViewController != nil
      }
    guard let window,
      let rootView = window.rootViewController?.view else {
      NSLog(
        "PiliPlus PiP: no host view scenes=\(scenes.count) windows=\(windows.count)"
      )
      return false
    }

    if hostView?.window !== window {
      hostView?.removeFromSuperview()
      let hostView = UIView(frame: rootView.bounds)
      hostView.isUserInteractionEnabled = false
      hostView.backgroundColor = .clear
      hostView.layer.addSublayer(displayLayer)
      rootView.insertSubview(hostView, at: 0)
      self.hostView = hostView
    }
    hostView?.frame = rootView.bounds
    displayLayer.frame = hostView?.bounds ?? rootView.bounds
    return true
  }

  func start(
    handle: Int64,
    position: Double,
    duration: Double,
    playing: Bool
  ) -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported(),
          attachDisplayLayer() else {
      NSLog("PiliPlus PiP: unsupported or no active window")
      return false
    }
    setupController()
    loggedFirstFrame = false
    self.handle = handle
    update(position: position, duration: duration, playing: playing)
    pendingStart = true
    NSLog(
      "PiliPlus PiP: requested possible=\(controller?.isPictureInPicturePossible == true) " +
        "layerStatus=\(displayLayer.status.rawValue) ready=\(displayLayer.isReadyForMoreMediaData)"
    )
    startIfPossible()
    return true
  }

  func update(position: Double, duration: Double, playing: Bool) {
    self.position = position
    self.duration = duration
    self.playing = playing
    controller?.invalidatePlaybackState()
  }

  func stop() {
    pendingStart = false
    controller?.stopPictureInPicture()
    handle = nil
    displayLayer.flushAndRemoveImage()
    hostView?.removeFromSuperview()
    hostView = nil
  }

  var isActiveOrPending: Bool {
    pendingStart || controller?.isPictureInPictureActive == true
  }

  func enqueue(handle: Int64, pixelBuffer: CVPixelBuffer) {
    guard self.handle == handle else { return }
    if displayLayer.status == .failed {
      displayLayer.flush()
    }
    guard displayLayer.isReadyForMoreMediaData else {
      if !loggedFirstFrame {
        loggedFirstFrame = true
        NSLog("PiliPlus PiP: display layer not ready for first frame")
      }
      return
    }

    let size = CGSize(
      width: CVPixelBufferGetWidth(pixelBuffer),
      height: CVPixelBufferGetHeight(pixelBuffer)
    )
    if formatDescription == nil || formatSize != size {
      formatSize = size
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
      )
    }
    guard let formatDescription else {
      NSLog("PiliPlus PiP: failed to create video format description")
      return
    }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMClockGetTime(hostClock),
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let result = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    guard result == noErr, let sampleBuffer else {
      NSLog("PiliPlus PiP: failed to create sample buffer: \(result)")
      return
    }

    CMSetAttachment(
      sampleBuffer,
      key: kCMSampleAttachmentKey_DisplayImmediately,
      value: kCFBooleanTrue,
      attachmentMode: kCMAttachmentMode_ShouldPropagate
    )
    displayLayer.enqueue(sampleBuffer)
    if !loggedFirstFrame {
      loggedFirstFrame = true
      NSLog(
        "PiliPlus PiP: first frame enqueued size=\(Int(size.width))x\(Int(size.height)) " +
          "layerStatus=\(displayLayer.status.rawValue) possible=\(controller?.isPictureInPicturePossible == true)"
      )
    }
    startIfPossible()
  }

  private func startIfPossible() {
    guard pendingStart,
          let controller,
          controller.isPictureInPicturePossible,
          !controller.isPictureInPictureActive else { return }
    pendingStart = false
    NSLog("PiliPlus PiP: starting")
    controller.startPictureInPicture()
  }
}

extension PictureInPictureController:
  AVPictureInPictureControllerDelegate,
  AVPictureInPictureSampleBufferPlaybackDelegate
{
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    NSLog("PiliPlus PiP: failed to start: \(error.localizedDescription)")
    pendingStart = false
    handle = nil
    displayLayer.flushAndRemoveImage()
    hostView?.removeFromSuperview()
    hostView = nil
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    pendingStart = false
    handle = nil
    displayLayer.flushAndRemoveImage()
    hostView?.removeFromSuperview()
    hostView = nil
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    self.playing = playing
    if let handle {
      onSetPlaying?(handle, playing)
    }
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    CMTimeRange(
      start: .zero,
      duration: duration > 0
        ? CMTime(seconds: duration, preferredTimescale: 600)
        : .positiveInfinity
    )
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    !playing
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    if let handle {
      let target = max(0, min(duration, position + skipInterval.seconds))
      position = target
      onSeek?(handle, target)
    }
    completionHandler()
  }
}
