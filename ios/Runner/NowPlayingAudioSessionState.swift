struct NowPlayingAudioSessionState {
  private var needsActivation = true

  mutating func update(
    playing: Bool,
    needsConfiguration: Bool,
    configure: () throws -> Void,
    activate: () throws -> Void
  ) throws {
    guard playing else {
      needsActivation = true
      return
    }

    if needsConfiguration {
      needsActivation = true
      try configure()
    }
    // A successful category change must not hide a failed activation.
    if needsActivation {
      try activate()
      needsActivation = false
    }
  }
}
