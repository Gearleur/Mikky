import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/settings.dart';
import 'package:mikky/settings/settings_controller.dart';
import 'package:mikky/theme.dart';
import 'package:mikky_engine/mikky_engine.dart';

void main() {
  test('rapid volume changes save only the latest complete state', () async {
    final writes = <Settings>[];
    final c = SettingsController(Settings(), write: (snapshot) async => writes.add(snapshot));
    addTearDown(c.dispose);
    await c.change((s) => s.volume = .1);
    await c.change((s) => s.volume = .9);
    await c.change((s) => s.theme = ThemeChoice.dark);
    expect(await c.flush(), isTrue);
    expect(writes, hasLength(1));
    expect(writes.single.volume, .9);
    expect(writes.single.theme, ThemeChoice.dark);
  });

  test('a write in progress never overlaps the next write or loses later input', () async {
    final gate = Completer<void>();
    final writes = <double>[];
    var active = 0, maximum = 0;
    final c = SettingsController(
      Settings(),
      write: (snapshot) async {
        active++;
        if (active > maximum) maximum = active;
        writes.add(snapshot.volume);
        if (writes.length == 1) await gate.future;
        active--;
      },
    );
    addTearDown(c.dispose);
    await c.change((s) => s.volume = .2);
    final saving = c.flush();
    await Future<void>.delayed(Duration.zero);
    await c.change((s) => s.volume = .8);
    gate.complete();
    expect(await saving, isTrue);
    expect(maximum, 1);
    expect(writes, [.2, .8]);
  });

  test('failed saving remains visible, retry preserves every live preference', () async {
    var fail = true;
    Settings? written;
    final c = SettingsController(
      Settings(),
      write: (snapshot) async {
        if (fail) throw const FileSystemException('test failure');
        written = snapshot;
      },
    );
    addTearDown(c.dispose);
    await c.change((s) => s.notifications = false);
    expect(await c.flush(), isFalse);
    expect(c.saveFailed, isTrue);
    expect(c.settings.notifications, isFalse);
    fail = false;
    expect(await c.flush(), isTrue);
    expect(c.error, isNull);
    expect(written!.notifications, isFalse);
  });

  test('saving waits for native effects queued while a flush is starting', () async {
    final gate = Completer<void>();
    final writes = <Settings>[];
    final c = SettingsController(
      Settings(),
      apply: (before, after) async {
        if (before.edge != after.edge) await gate.future;
      },
      write: (snapshot) async => writes.add(snapshot),
    );
    addTearDown(c.dispose);
    await c.change((s) => s.volume = .7);
    final saving = c.flush();
    final moving = c.change((s) => s.edge = IslandEdge.right);
    await Future<void>.delayed(Duration.zero);
    expect(writes, isEmpty);
    gate.complete();
    await moving;
    expect(await saving, isTrue);
    expect(writes.single.edge, IslandEdge.right);
  });

  test('a refused native effect restores its field without losing later volume input', () async {
    final gate = Completer<void>();
    final c = SettingsController(
      Settings(),
      apply: (before, after) async {
        if (before.edge != after.edge) {
          await gate.future;
          throw StateError('native refusal');
        }
      },
      write: (_) async {},
    );
    addTearDown(c.dispose);
    final moving = c.change((s) => s.edge = IslandEdge.right);
    final volume = c.change((s) => s.volume = .9);
    gate.complete();
    await Future.wait([moving, volume]);
    expect(c.settings.edge, IslandEdge.top);
    expect(c.settings.volume, .9);
    expect(c.applyError, isNotNull);
  });

  test('atomic replacement can be loaded again and a failed write preserves the previous file', () async {
    final dir = await Directory.systemTemp.createTemp('mikky-settings-file-');
    try {
      final file = File('${dir.path}/settings.json');
      await Settings(sound: false).write(file);
      await Settings(theme: ThemeChoice.dark, edge: IslandEdge.right, volume: .83).write(file);
      final loaded = Settings.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);
      expect(loaded.theme, ThemeChoice.dark);
      expect(loaded.edge, IslandEdge.right);
      expect(loaded.volume, .83);
      final previous = await file.readAsString();
      await expectLater(Settings().write(File('${file.path}/invalid.json')), throwsA(isA<FileSystemException>()));
      expect(await file.readAsString(), previous);
      expect(await dir.list().length, 1);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
