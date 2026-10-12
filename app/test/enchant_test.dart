import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/agents/enchant.dart';
import 'package:mikky/home/home_app_tile.dart';
import 'package:mikky/home/home_layout.dart';
import 'package:mikky/side/home_screen.dart';
import 'package:mikky/ui/foundation/status.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// « Ensorcelé »: stopped by its limit, the agent is relaunched by itself
/// once the limit lifts; hit again, it waits for the next reset. (Test
/// timers are simulated: `tester.pump` moves time on.)
void main() {
  testWidgets('home tile updates as soon as the relaunch is scheduled or cancelled', (tester) async {
    final now = DateTime.now();
    final entry = AgentEntry('tile', AgentProvider.claude, AgentHost.windows, AgentOrigin.external, 'p', now)
      ..status = AgentStatus.rateLimited
      ..failure = (SessionLog()
        ..apply(TurnStarted(at: now))
        ..apply(TurnEnded(StopReason.rateLimited, at: now)));
    final spells = Enchantments.instance;
    try {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MikkyUiTheme(
              ui: MikkyUi.light,
              child: HomeScreen(entries: [entry], open: (_) {}, canLaunch: false, layout: HomeLayout.rightTiles),
            ),
          ),
        ),
      );
      expect(tester.widget<HomeAppTile>(find.byType(HomeAppTile)).app.status, UiStatus.limited);
      spells.enchant(entry.id, null, (_) async {});
      await tester.pump();
      expect(tester.widget<HomeAppTile>(find.byType(HomeAppTile)).app.status, isNull);
      spells.cancel(entry.id);
      await tester.pump();
      expect(tester.widget<HomeAppTile>(find.byType(HomeAppTile)).app.status, UiStatus.limited);
    } finally {
      spells.cancel(entry.id);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('scheduled relaunch removes the yellow state immediately; cancelling restores it', (tester) async {
    final spells = Enchantments.instance;
    const limited = Agent(id: 'limited', name: 'Limité', status: AgentStatus.rateLimited, startedAt: 0, statusSince: 1);
    const working = Agent(id: 'limited', name: 'Au travail', status: AgentStatus.working, startedAt: 0, statusSince: 2);
    try {
      expect(spells.attentionAgents([limited]), [limited]);
      spells.enchant(limited.id, null, (_) async {});
      expect(spells.attentionAgents([limited]), isEmpty);
      expect(limited.status, AgentStatus.rateLimited, reason: 'the session itself still knows its actual limit');
      expect(spells.attentionAgents([working]), [working], reason: 'a resumed agent is visible immediately');
      spells.cancel(limited.id);
      expect(spells.attentionAgents([limited]), [limited]);
    } finally {
      spells.cancel(limited.id);
    }
  });

  testWidgets('relaunches after the reset, and again if the limit is back', (tester) async {
    final spells = Enchantments.instance;
    final sent = <String>[];
    Future<void> send(String t) async => sent.add(t);
    final now = DateTime(2026, 9, 30, 14);
    spells.enchant('a', now.add(const Duration(hours: 3)), send, now: now);
    expect(spells.isOn('a'), isTrue);
    expect(spells.relaunchAt('a'), now.add(const Duration(hours: 3, minutes: 1)));
    await tester.pump(const Duration(hours: 3));
    expect(sent, isEmpty);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(sent, [Enchantments.resumeMessage]);
    // Sent, waiting to see it through.
    expect(spells.isOn('a'), isTrue);
    expect(spells.relaunchAt('a'), isNull);
    // The limit again: waits for the next reset (unknown: 30 min).
    spells.limitedAgain('a', DateTime.now().add(const Duration(seconds: 1)), null, send);
    expect(spells.relaunchAt('a'), isNotNull);
    await tester.pump(const Duration(minutes: 32));
    expect(sent, hasLength(2));
    // Through: the spell is over.
    spells.done('a');
    expect(spells.isOn('a'), isFalse);
  });

  testWidgets('cancelled: nothing is sent', (tester) async {
    final spells = Enchantments.instance;
    final sent = <String>[];
    spells.enchant('b', null, (t) async => sent.add(t), now: DateTime(2026, 9, 30, 14));
    spells.cancel('b');
    await tester.pump(const Duration(hours: 1));
    expect(sent, isEmpty);
    expect(spells.isOn('b'), isFalse);
  });
}
