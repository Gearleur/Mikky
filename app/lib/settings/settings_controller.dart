import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings.dart';

typedef SettingsEffect = Future<void> Function(Settings before, Settings after);
typedef SettingsWriter = Future<void> Function(Settings snapshot);

/// One live state for the page, menus and shortcuts. Native effects are
/// ordered; disk writes coalesce slider events and never overlap.
class SettingsController extends ChangeNotifier {
  SettingsController(this.settings, {this.apply, SettingsWriter? write})
    : _write = write ?? ((snapshot) => snapshot.save(reportErrors: true));

  final Settings settings;
  final SettingsEffect? apply;
  final SettingsWriter _write;
  Timer? _saveTimer;
  Future<void> _effects = Future.value();
  Future<bool>? _writing;
  int _revision = 0, _saved = 0;
  bool _disposed = false;
  bool saveFailed = false;
  String? applyError;

  String? get error => applyError ?? (saveFailed ? 'Sauvegarde impossible' : null);

  Future<void> change(void Function(Settings) update) {
    if (_disposed) return Future.value();
    final before = settings.copy();
    update(settings);
    final after = settings.copy();
    settings.restore(after);
    if (mapEquals(before.toJson(), after.toJson())) return Future.value();
    _revision++;
    applyError = null;
    _notify();
    _effects = _effects.then((_) async {
      if (_disposed) return;
      try {
        await apply?.call(before, after);
      } catch (_) {
        final current = settings.toJson();
        final previous = before.toJson();
        final requested = after.toJson();
        for (final key in previous.keys) {
          if (previous[key] != requested[key] && current[key] == requested[key]) current[key] = previous[key];
        }
        settings.restore(Settings.fromJson(current));
        applyError = 'Réglage non appliqué';
        _notify();
      }
      if (!_disposed) {
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 220), () => unawaited(flush()));
      }
    });
    return _effects;
  }

  /// Explicit retry and shutdown both wait for the latest complete state.
  Future<bool> flush() {
    _saveTimer?.cancel();
    if (_writing case final writing?) return writing;
    final writing = _save();
    _writing = writing;
    unawaited(writing.then((_) => _writing = null));
    return writing;
  }

  Future<bool> _save() async {
    while (_saved < _revision || saveFailed) {
      while (true) {
        final effects = _effects;
        await effects;
        if (identical(effects, _effects)) break;
      }
      final revision = _revision;
      try {
        await _write(settings.copy());
        _saved = revision;
        saveFailed = false;
      } catch (_) {
        saveFailed = true;
        _notify();
        return false;
      }
    }
    _notify();
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    super.dispose();
  }
}
