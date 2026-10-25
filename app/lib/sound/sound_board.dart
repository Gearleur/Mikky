import 'package:mikky_engine/mikky_engine.dart';

import '../overlay/overlay_channel.dart';
import '../settings.dart';
import 'sound_profile.dart';

/// Plays Mikky's sounds: off or on and how loud in the settings, never two
/// of the same within [_again], never more than a few at once.
class SoundBoard {
  SoundBoard(this._overlay, this._settings, {required this.profile, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final OverlayChannel _overlay;
  final Settings _settings;
  final SoundProfile profile;
  final DateTime Function() _now;

  static const _again = Duration(milliseconds: 150);
  static const _window = Duration(milliseconds: 600);
  static const _maxInWindow = 3;

  final Map<String, DateTime> _lastPlayed = {};
  final List<DateTime> _recent = [];

  /// Opens every file once (call when the app starts).
  void preload() {
    if (_settings.sound) _overlay.preloadSounds(profile.assets);
  }

  void play(MikkyCue cue) {
    final file = profile[cue];
    if (file == null || !_settings.sound || _settings.volume <= 0) return;
    final now = _now();
    final last = _lastPlayed[file];
    if (last != null && now.difference(last) < _again) return;
    _recent.removeWhere((t) => now.difference(t) > _window);
    if (_recent.length >= _maxInWindow) return;
    _recent.add(now);
    _lastPlayed[file] = now;
    _overlay.playSound(file, _settings.volume);
  }
}
