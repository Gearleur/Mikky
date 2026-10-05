import 'package:mikky_engine/mikky_engine.dart';

import '../overlay/overlay_channel.dart';
import '../settings.dart';

/// Which file each of Mikky's sounds plays (2026-10-04: the PSP sounds the
/// user put in `app/assets/sounds/`, « je veux cette atmosphère »). One
/// place to change, with the user, sound by sound (plan of 2026-10-05).
/// Null: silent.
const Map<MikkyCue, String?> soundFiles = {
  MikkyCue.hello: 'launch',
  // Opening and closing the island (user, 2026-10-05).
  MikkyCue.open: 'discord_open',
  MikkyCue.close: 'discord_close',
  MikkyCue.peek: 'navigate',
  MikkyCue.navigate: 'navigate',
  MikkyCue.back: 'back',
  MikkyCue.select: 'select',
  MikkyCue.launch: 'navigate',
  MikkyCue.send: 'select',
  MikkyCue.approval: 'folder_open',
  MikkyCue.question: 'folder_open',
  MikkyCue.error: 'back',
  MikkyCue.rateLimited: 'back',
  MikkyCue.finished: 'retroachievements',
  MikkyCue.approve: 'select',
  MikkyCue.deny: 'back',
  MikkyCue.love: 'navigate',
  MikkyCue.slap: 'back',
  MikkyCue.dizzy: 'back',
  MikkyCue.sleep: 'folder_close',
  MikkyCue.wake: 'folder_open',
};

/// Plays Mikky's sounds: off or on and how loud in the settings, never two
/// of the same within [_again], never more than a few at once.
class SoundBoard {
  SoundBoard(this._overlay, this._settings, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final OverlayChannel _overlay;
  final Settings _settings;
  final DateTime Function() _now;

  static const _again = Duration(milliseconds: 150);
  static const _window = Duration(milliseconds: 600);
  static const _maxInWindow = 3;

  final Map<String, DateTime> _lastPlayed = {};
  final List<DateTime> _recent = [];

  /// Opens every file once (call when the app starts).
  void preload() {
    if (_settings.sound) _overlay.preloadSounds({for (final f in soundFiles.values) ?f});
  }

  void play(MikkyCue cue) {
    final file = soundFiles[cue];
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
