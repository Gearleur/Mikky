import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/overlay/overlay_channel.dart';
import 'package:mikky/settings.dart';
import 'package:mikky/sound/sound_board.dart';
import 'package:mikky/sound/sound_profile.dart';
import 'package:mikky/sound/sound_profile_loader.dart';
import 'package:mikky_engine/mikky_engine.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.source);
  final String? source;

  @override
  Future<ByteData> load(String key) async {
    expect(key, defaultSoundProfileAsset);
    if (source == null) throw StateError('Asset unavailable');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source!)));
  }
}

class _Overlay extends OverlayChannel {
  final played = <(String, double)>[];
  final preloaded = <String>{};

  @override
  void playSound(String name, double volume) => played.add((name, volume));

  @override
  void preloadSounds(Iterable<String> names) => preloaded.addAll(names);
}

Map<String, Object?> overrides(Map<String, Object?> sounds) => {'version': 1, 'sounds': sounds};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String source;
  late SoundProfile defaults;
  setUpAll(() async {
    source = await File(defaultSoundProfileAsset).readAsString();
    defaults = SoundProfile.decode(source);
  });

  test('the bundled JSON covers every cue and round-trips without mutable state', () {
    expect(defaults.files.keys.toSet(), MikkyCue.values.toSet());
    expect(SoundProfile.fromJson(defaults.toJson()).files, defaults.files);
    expect(() => defaults.files[MikkyCue.open] = null, throwsUnsupportedError);
  });

  test('partial overrides inherit defaults and explicit null means silence', () {
    final profile = SoundProfile.fromJson(overrides({'open': 'select_2', 'back': null}), defaults: defaults);
    expect(profile[MikkyCue.open], 'select_2');
    expect(profile[MikkyCue.back], isNull);
    expect(profile[MikkyCue.finished], defaults[MikkyCue.finished]);
    expect(defaults[MikkyCue.open], 'discord_open');
  });

  test('invalid structures and versions are rejected', () {
    for (final input in [
      <String, Object?>{},
      {'version': 2, 'sounds': <String, Object?>{}},
      {'version': 1.0, 'sounds': <String, Object?>{}},
      {'version': 1, 'sounds': <Object?>[]},
      {'version': 1, 'sounds': <String, Object?>{}, 'volume': 0},
      overrides({'opne': 'select'}),
      overrides({'open': 1}),
    ]) {
      expect(() => SoundProfile.fromJson(input, defaults: defaults), throwsFormatException);
    }
    expect(() => SoundProfile.decode('[]'), throwsFormatException);
    expect(() => SoundProfile.decode('{'), throwsFormatException);
    expect(() => SoundProfile.fromJson(overrides({})), throwsFormatException);
  });

  test('asset names obey the native reader contract, without paths or extensions', () {
    for (final name in ['', '../back', r'C:\back', 'back.mp3', 'Back', 'back sound', 'back\n', 'x' * 65]) {
      expect(() => SoundProfile.fromJson(overrides({'open': name}), defaults: defaults), throwsFormatException);
    }
    final profile = SoundProfile.fromJson(overrides({'open': 'x' * 64}), defaults: defaults);
    expect(profile[MikkyCue.open], 'x' * 64);
  });

  group('profile loading', () {
    late Directory directory;
    late File file;
    final warnings = <String>[];
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mikky-sound-profile-');
      file = File('${directory.path}/sounds.json');
      warnings.clear();
    });
    tearDown(() async {
      if (await file.exists()) await file.delete();
      await directory.delete();
    });

    Future<SoundProfile> load() => loadSoundProfile(bundle: _Bundle(source), userFile: file, onWarning: warnings.add);

    test('an absent personal profile uses the bundled JSON without writing a file', () async {
      expect((await load()).files, defaults.files);
      expect(await file.exists(), isFalse);
      expect(warnings, isEmpty);
    });

    test('a personal override applies only the requested cues', () async {
      await file.writeAsString(jsonEncode(overrides({'open': 'select_2', 'close': null})));
      final loaded = await load();
      expect(loaded[MikkyCue.open], 'select_2');
      expect(loaded[MikkyCue.close], isNull);
      expect(loaded[MikkyCue.finished], defaults[MikkyCue.finished]);
      expect(warnings, isEmpty);
    });

    test('a malformed personal profile is rejected entirely and never overwritten', () async {
      final invalid = jsonEncode(overrides({'open': 'select_2', 'unknown': 'select'}));
      await file.writeAsString(invalid);
      expect((await load()).files, defaults.files);
      expect(await file.readAsString(), invalid);
      expect(warnings, hasLength(1));
    });

    test('an unavailable bundled profile stays silent without blocking startup', () async {
      final loaded = await loadSoundProfile(bundle: _Bundle(null), userFile: file, onWarning: warnings.add);
      expect(loaded.assets, isEmpty);
      expect(loaded.files.values, everyElement(isNull));
      expect(warnings, hasLength(1));
    });
  });

  test('playback and preloading use the injected profile and existing volume preference', () {
    final profile = SoundProfile.fromJson(overrides({'open': 'select_2', 'back': null}), defaults: defaults);
    final overlay = _Overlay();
    final settings = Settings(volume: .35);
    final board = SoundBoard(overlay, settings, profile: profile);
    board
      ..preload()
      ..play(MikkyCue.open)
      ..play(MikkyCue.back);
    expect(overlay.preloaded, profile.assets);
    expect(overlay.played, [('select_2', .35)]);
    settings.sound = false;
    board.play(MikkyCue.finished);
    expect(overlay.played, hasLength(1));
  });
}
