// Run from the repo root:
// swiftc ios/Runner/NowPlayingAudioSessionState.swift test/ios/now_playing_audio_session_test.swift -o /tmp/now_playing_audio_session_test
// /tmp/now_playing_audio_session_test

@main
enum NowPlayingAudioSessionTests {
  enum Failure: Error {
    case configuration
    case activation
  }

  static func main() throws {
    var state = NowPlayingAudioSessionState()
    var needsConfiguration = true
    var configurations = 0
    var activations = 0

    // Configuration succeeds, but the first activation fails.
    do {
      try state.update(
        playing: true,
        needsConfiguration: needsConfiguration,
        configure: {
          configurations += 1
          needsConfiguration = false
        },
        activate: {
          activations += 1
          throw Failure.activation
        }
      )
      preconditionFailure("Activation failure was swallowed")
    } catch Failure.activation {}

    let configure = { configurations += 1 }
    let activate = { activations += 1 }
    try state.update(
      playing: true, needsConfiguration: needsConfiguration,
      configure: configure, activate: activate
    )
    assert(configurations == 1 && activations == 2, "Activation must retry without reconfiguring")

    for _ in 0..<10 {
      try state.update(
        playing: true, needsConfiguration: false,
        configure: configure, activate: activate
      )
    }
    assert(activations == 2, "Position updates must not reactivate a working session")

    try state.update(
      playing: false, needsConfiguration: true,
      configure: configure, activate: activate
    )
    assert(configurations == 1 && activations == 2, "Paused updates must not change the session")
    try state.update(
      playing: true, needsConfiguration: false,
      configure: configure, activate: activate
    )
    assert(activations == 3, "Resuming must activate even when the category is correct")

    // An external category change requires activation again after correction.
    try state.update(
      playing: true, needsConfiguration: true,
      configure: configure, activate: activate
    )
    assert(configurations == 2 && activations == 4)

    do {
      try state.update(
        playing: true, needsConfiguration: true,
        configure: { throw Failure.configuration }, activate: activate
      )
      preconditionFailure("Configuration failure was swallowed")
    } catch Failure.configuration {}
    assert(activations == 4, "Failed configuration must not activate an incorrect session")
    try state.update(
      playing: true, needsConfiguration: true,
      configure: configure, activate: activate
    )
    assert(configurations == 3 && activations == 5, "Configuration failure must be recoverable")

    print("Now Playing audio session recovery tests passed")
  }
}
