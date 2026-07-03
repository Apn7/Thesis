import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Short non-vocal audio cues ("earcons") for the push-to-talk flow.
///
/// A blind user holding the volume button cannot *see* the "শুনছি..." label,
/// and speaking a status word would itself be captured by the microphone. So
/// the mic states are marked with two instantly recognisable chimes instead:
///
///   * **listen-start** — rising two-note chime on press. [playListenStart]
///     completes only after the chime has finished, so the caller opens the
///     microphone with **zero overlap** between playback and capture.
///   * **listen-stop** — falling two-note chime played after release, once
///     capture has been torn down: "got it, processing."
///
/// ## Why the sequencing and audio context are load-bearing
///
/// The STT path records via the `record` plugin (`AudioRecorder.startStream`).
/// audioplayers' default context requests full audio focus
/// (`AndroidAudioFocus.gain`) — playing a chime at the same instant the
/// recorder opens contends over the same Android `AudioManager` and can
/// silently kill the capture stream (observed: STT receives no audio at all).
/// Two rules therefore apply to every player this app runs alongside the mic:
///
///   1. [noFocusContext]: request **no audio focus** and mix with others, so
///      playback can never re-route or steal the session out from under the
///      recorder (or pause the TTS). `usageType: media` keeps the sound on
///      STREAM_MUSIC — the stream MainActivity pins to max volume.
///   2. Never start playback while capture is starting: the start chime ends
///      before the mic opens; the stop chime waits for teardown.
///
/// Failures degrade gracefully: the voice pipeline never depends on earcons.
class EarconService {
  static EarconService? _instance;

  static EarconService get instance {
    _instance ??= EarconService._();
    return _instance!;
  }

  EarconService._();

  /// Length of the listen_start.wav asset plus a scheduling margin. Must
  /// track the asset (see generate_alert_sounds.py) — this is how long the
  /// microphone open is deferred on every push-to-talk press.
  static const Duration startChimeLength = Duration(milliseconds: 230);

  /// Playback context for sounds that must coexist with the microphone and
  /// TTS: no audio focus, mixes with others, stays on the max-pinned media
  /// stream. Shared with HomeScreen's CRITICAL alarm player, which can fire
  /// mid-dictation.
  static AudioContext get noFocusContext => AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  final AudioPlayer _startPlayer = AudioPlayer();
  final AudioPlayer _stopPlayer = AudioPlayer();
  bool _ready = false;

  /// Preload both chimes. Safe to call more than once.
  Future<void> initialize() async {
    if (_ready) return;
    try {
      // Context first, before any source is prepared. Unsupported on the
      // Windows backend — a failure here must not disable the earcons.
      try {
        await _startPlayer.setAudioContext(noFocusContext);
        await _stopPlayer.setAudioContext(noFocusContext);
      } catch (e) {
        debugPrint('[EARCON] audio context not applied: $e');
      }
      await _startPlayer.setReleaseMode(ReleaseMode.stop);
      await _stopPlayer.setReleaseMode(ReleaseMode.stop);
      await _startPlayer.setSource(AssetSource('alerts/listen_start.wav'));
      await _stopPlayer.setSource(AssetSource('alerts/listen_stop.wav'));
      _ready = true;
      debugPrint('[EARCON] listen chimes preloaded');
    } catch (e) {
      debugPrint('[EARCON] !! preload failed: $e');
    }
  }

  /// Rising chime — about to listen. Completes once playback has finished
  /// (bounded by [startChimeLength]), so the caller can open the microphone
  /// immediately after with no playback/capture overlap. Returns at once when
  /// the chimes aren't ready, never delaying the mic on a broken player.
  Future<void> playListenStart() async {
    if (!_ready) return;
    try {
      await _replay(_startPlayer);
      await Future<void>.delayed(startChimeLength);
    } catch (e) {
      debugPrint('[EARCON] !! start chime failed: $e');
    }
  }

  /// Falling chime — utterance submitted. Fire-and-forget; call only after
  /// capture has been torn down.
  Future<void> playListenStop() async {
    if (!_ready) return;
    try {
      await _replay(_stopPlayer);
    } catch (e) {
      debugPrint('[EARCON] !! stop chime failed: $e');
    }
  }

  /// Restart [player] from the top. A rapid re-press within the chime's
  /// duration restarts it cleanly instead of overlapping or being dropped.
  Future<void> _replay(AudioPlayer player) async {
    await player.stop();
    await player.seek(Duration.zero);
    await player.resume();
  }
}
