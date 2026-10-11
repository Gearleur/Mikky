import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/island/deadline_timer.dart';
import 'package:mikky/island/island_hotkeys.dart';
import 'package:mikky/island/island_menu.dart';
import 'package:mikky/island/island_notifier.dart';
import 'package:mikky/settings.dart';
import 'package:mikky_engine/mikky_engine.dart';

Agent _agent(String id, AgentStatus status, {String detail = ''}) =>
    Agent(id: id, name: 'Agent $id', status: status, startedAt: 0, statusSince: 0, detail: detail);

void main() {
  group('menu', () {
    test('every item comes back from its id; 0 (the separator) and unknown ids are none', () {
      for (final item in IslandMenuItem.values) {
        expect(IslandMenuItem.byId(item.id), item);
      }
      expect(IslandMenuItem.byId(0), isNull);
      expect(IslandMenuItem.byId(null), isNull);
      expect(IslandMenuItem.byId(IslandMenuItem.values.length + 1), isNull);
    });

    test('the agents\' entries only when Mikky can launch them, the volume only with sounds', () {
      List<int> ids({required bool canLaunch, required bool sound}) => [
        for (final e in islandMenuEntries(
          settings: Settings()..sound = sound,
          demo: false,
          canLaunch: canLaunch,
          autostart: false,
          autoRelaunch: false,
        ))
          e.id,
      ];
      final all = ids(canLaunch: true, sound: true);
      expect(all, containsAll([IslandMenuItem.stopAll.id, IslandMenuItem.volumeMid.id]));
      expect(ids(canLaunch: false, sound: true), isNot(contains(IslandMenuItem.stopAll.id)));
      expect(ids(canLaunch: true, sound: false), isNot(contains(IslandMenuItem.volumeMid.id)));
      expect(all.last, IslandMenuItem.quit.id);
    });
  });

  test('every shortcut comes back from its id', () {
    for (final key in IslandHotkey.values) {
      expect(IslandHotkey.byId(key.id), key);
    }
    expect(IslandHotkey.byId(99), isNull);
  });

  group('notifications', () {
    test('once per agent and state, never while the window is open, again after a change', () {
      final shown = <String>[];
      final notifier = IslandNotifier((title, body) => shown.add('$title: $body'));
      void update(List<Agent> agents, {bool open = false}) => notifier.update(agents, enabled: true, windowOpen: open);

      update([_agent('a', AgentStatus.approval, detail: 'cargo test')]);
      update([_agent('a', AgentStatus.approval, detail: 'cargo test')]);
      expect(shown, ['Agent a: Attend ton feu vert : cargo test']);
      expect(notifier.lastAgent, 'a');

      update([_agent('b', AgentStatus.finished)], open: true);
      expect(shown, hasLength(1));
      // Seen while open: not shown later either.
      update([_agent('b', AgentStatus.finished)]);
      expect(shown, hasLength(1));

      update([_agent('b', AgentStatus.working)]);
      update([_agent('b', AgentStatus.error)]);
      expect(shown.last, 'Agent b: Erreur');
    });

    test('off: nothing shows', () {
      final shown = <String>[];
      IslandNotifier((t, b) => shown.add(t))
          .update([_agent('a', AgentStatus.error)], enabled: false, windowOpen: false);
      expect(shown, isEmpty);
    });
  });

  test('the deadline timer fires once, at the nearest deadline', () {
    fakeAsync((FakeAsync async) {
      var fired = 0;
      final timer = DeadlineTimer(() => fired++);
      timer.schedule([null, 2.0, 1.0], now: 0);
      // A later deadline does not move the timer already set.
      timer.schedule([3.0], now: 0);
      async.elapse(const Duration(milliseconds: 990));
      expect(fired, 0);
      async.elapse(const Duration(milliseconds: 20));
      expect(fired, 1);
      async.elapse(const Duration(seconds: 5));
      expect(fired, 1);

      timer.schedule([1.0], now: 0);
      timer.cancel();
      async.elapse(const Duration(seconds: 2));
      expect(fired, 1);
    });
  });
}
