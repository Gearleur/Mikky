import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'theme.dart';

/// User settings kept between launches, in `%APPDATA%\Mikky\settings.json`.
/// Nothing secret goes here.
class Settings {
  Settings({
    this.theme = ThemeChoice.auto,
    this.edge = IslandEdge.top,
    this.notifications = true,
    this.autoRelaunch = false,
    this.sound = true,
    this.volume = .5,
    this.hotkeys = true,
  });

  ThemeChoice theme;

  /// Windows notifications when an agent waits, fails or finishes.
  bool notifications;

  /// « Relance automatique »: agents stopped by a subscription's limit go
  /// on by themselves when it lifts (the home's switch).
  bool autoRelaunch;

  /// Where the island lives: top center or right edge.
  IslandEdge edge;

  /// Mikky's sounds, and how loud (0..1).
  bool sound;
  double volume;

  /// The global shortcuts (Ctrl + Alt + A, Espace, M).
  bool hotkeys;

  static File? get _file {
    final appData = Platform.environment['APPDATA'];
    return appData == null ? null : File('$appData\\Mikky\\settings.json');
  }

  static Future<Settings> load() async {
    try {
      final file = _file;
      if (file == null || !await file.exists()) return Settings();
      final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return Settings(
        theme: ThemeChoice.values.asNameMap()[json['theme']] ?? ThemeChoice.auto,
        edge: IslandEdge.values.asNameMap()[json['edge']] ?? IslandEdge.top,
        notifications: json['notifications'] as bool? ?? true,
        autoRelaunch: json['autoRelaunch'] as bool? ?? false,
        sound: json['sound'] as bool? ?? true,
        volume: ((json['volume'] as num?)?.toDouble() ?? .5).clamp(0.0, 1.0),
        hotkeys: json['hotkeys'] as bool? ?? true,
      );
    } catch (e) {
      debugPrint('mikky: settings unreadable, using defaults ($e)');
      return Settings();
    }
  }

  static File? get _tuningFile {
    final appData = Platform.environment['APPDATA'];
    return appData == null ? null : File('$appData\\Mikky\\tuning.json');
  }

  /// Mikky's proportions saved by the tuning screen, or the defaults.
  static Future<MikkyTuning> loadTuning() async {
    try {
      final file = _tuningFile;
      if (file == null || !await file.exists()) return MikkyTuning();
      return MikkyTuning.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);
    } catch (e) {
      debugPrint('mikky: tuning unreadable, using defaults ($e)');
      return MikkyTuning();
    }
  }

  static Future<void> saveTuning(MikkyTuning tuning) async {
    final file = _tuningFile;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(tuning.toJson()));
  }

  Future<void> save() async {
    try {
      final file = _file;
      if (file == null) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'theme': theme.name,
          'edge': edge.name,
          'notifications': notifications,
          'autoRelaunch': autoRelaunch,
          'sound': sound,
          'volume': volume,
          'hotkeys': hotkeys,
        }),
      );
    } catch (e) {
      debugPrint('mikky: settings not saved ($e)');
    }
  }
}
