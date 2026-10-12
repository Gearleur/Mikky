import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/agents/agents_service.dart';
import 'package:mikky/agents/enchant.dart';
import 'package:mikky/side/session_menu.dart';
import 'package:mikky/side/side_app.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

class _RunningAgent implements AgentRun {
  @override
  final log = SessionLog()..apply(const TurnStarted());
  int stops = 0;
  @override
  bool get alive => stops == 0;
  @override
  String get sessionId => 'session';
  @override
  Future<void> stop() async {
    stops++;
    log.apply(const TurnEnded(StopReason.cancelled));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final confirm in [false, true]) {
    test('delete is available while working; confirmation=$confirm', () async {
      final dir = await Directory.systemTemp.createTemp('mikky-session-menu-');
      final store = AgentStore(File('${dir.path}/agents.json'));
      store.agents.add(
        StoredAgent(
          id: 'agent',
          provider: AgentProvider.claude,
          host: AgentHost.windows,
          cwd: dir.path,
          permissions: PermissionMode.ask,
          createdAt: DateTime.now(),
          sessionId: 'session',
        ),
      );
      final service = AgentsService(clock: () => 0, store: store);
      final entry = service.source.entry('agent')!;
      final run = _RunningAgent();
      entry.run = run;
      var menus = 0, removed = false;
      final spells = Enchantments.instance;
      spells.enchant(entry.id, DateTime.now().add(const Duration(hours: 1)), (_) async {});
      final host = SideHost(
        service: service,
        answer: (_, _) {},
        pickFolder: (_) async => null,
        islandMenu: () {},
        showMenu: (entries) async {
          menus++;
          if (menus == 1) return entries.singleWhere((e) => e.label == 'Supprimer…').id;
          return confirm ? entries.singleWhere((e) => e.label.startsWith('Supprimer de Mikky')).id : null;
        },
      );
      try {
        await showSessionMenu(host, entry, rename: () {}, deleted: () => removed = true);
        expect(menus, 2);
        expect(run.stops, confirm ? 1 : 0);
        expect(entry.mark.forgotten, confirm);
        expect(removed, confirm);
        expect(spells.isOn(entry.id), !confirm);
        expect(service.source.homeEntries.isEmpty, confirm);
      } finally {
        spells.cancel(entry.id);
        await service.shutdown();
        service.dispose();
        await dir.delete(recursive: true);
      }
    });
  }
}
