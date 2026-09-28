import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'theme.dart';

/// User settings kept between launches, in `%APPDATA%\Mikky\settings.json`.
/// Nothing secret goes here.
class Settings {
  Settings({this.theme = ThemeChoice.auto});

  ThemeChoice theme;

  static File? get _file {
    final appData = Platform.environment['APPDATA'];
    return appData == null ? null : File('$appData\\Mikky\\settings.json');
  }

  static Future<Settings> load() async {
    try {
      final file = _file;
      if (file == null || !await file.exists()) return Settings();
      final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return Settings(theme: ThemeChoice.values.asNameMap()[json['theme']] ?? ThemeChoice.auto);
    } catch (e) {
      debugPrint('mikky: settings unreadable, using defaults ($e)');
      return Settings();
    }
  }

  Future<void> save() async {
    try {
      final file = _file;
      if (file == null) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'theme': theme.name}));
    } catch (e) {
      debugPrint('mikky: settings not saved ($e)');
    }
  }
}
