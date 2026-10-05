import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/island/content/brief_view.dart';
import 'package:mikky/overlay/overlay_channel.dart';
import 'package:mikky/settings.dart';
import 'package:mikky/sound/sound_board.dart';
import 'package:mikky/ui/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'load_fonts.dart';

final _t0 = DateTime.utc(2026, 10, 4, 12);

SessionLog _waiting() => SessionLog()
  ..apply(const SessionStarted('s1', cwd: r'C:\dev\mikky'))
  ..apply(TurnStarted(at: _t0))
  ..apply(UserMessage('Corrige le build Windows et relance les tests du moteur, puis dis-moi ce qui casse encore', at: _t0))
  ..apply(const PlanChanged([PlanEntry('Lire', PlanStatus.completed), PlanEntry('Lancer les tests', PlanStatus.inProgress)]))
  ..apply(AgentMessage('J’ai corrigé le CMake.\n\nJe relance maintenant toute la suite de tests, ça prend une minute.', at: _t0))
  ..apply(const ToolCallEvent('t0', kind: ToolKind.edit, diff: FileDiff('windows/CMakeLists.txt', 'a\nb', 'a\nc\nd'), status: ToolStatus.completed))
  ..apply(const ToolCallEvent('t1', name: 'Bash', kind: ToolKind.execute, title: 'cargo test', command: 'cargo test --workspace --all-features -- --nocapture', status: ToolStatus.pending))
  ..apply(const PermissionAsked(1, toolCallId: 't1', title: 'Bash', options: [PermissionOption('a', 'Toujours', 'allow_always')]));

Agent _agent(AgentStatus s) => Agent(
  id: 'a',
  name: 'Build Windows qui casse depuis hier soir',
  status: s,
  startedAt: 0,
  statusSince: 0,
  provider: AgentProvider.claude,
  host: AgentHost.wsl,
  cwd: r'C:\dev\mikky',
);

class _FakeOverlay extends OverlayChannel {
  final played = <String>[];

  @override
  void playSound(String name, double volume) => played.add(name);
}

void main() {
  setUpAll(loadAppFonts);

  Widget host(Widget child, {double width = 328}) => MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MikkyUiTheme(
        ui: MikkyUi.dark,
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: SingleChildScrollView(child: child))),
      ),
    ),
  );

  testWidgets('an approval: task, step, last words, command, Oui / Non / Toujours', (tester) async {
    final answers = <AgentAnswer>[];
    var opened = false;
    final log = _waiting();
    await tester.pumpWidget(host(BriefView(
      agent: _agent(AgentStatus.approval),
      brief: briefOf(log, log.statusAt(_t0)),
      canAlways: true,
      queue: 2,
      actions: BriefActions(answer: answers.add, open: () => opened = true),
    )));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('attend ton feu vert'), findsOneWidget);
    expect(find.textContaining('Lancer les tests'), findsOneWidget);
    expect(find.textContaining('Je relance maintenant'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.textContaining('+2'), findsWidgets);
    await tester.tap(find.text('Oui'));
    await tester.tap(find.text('Toujours'));
    await tester.tap(find.text('Voir l’agent'));
    expect(answers, [AgentAnswer.allow, AgentAnswer.allowAlways]);
    expect(opened, isTrue);
  });

  testWidgets('every kind lays out at the top width and at the right width', (tester) async {
    final log = _waiting();
    for (final width in [328.0, 308.0]) {
      for (final s in [AgentStatus.approval, AgentStatus.question, AgentStatus.error, AgentStatus.finished, AgentStatus.rateLimited]) {
        await tester.pumpWidget(host(
          BriefView(key: ValueKey('$s$width'), agent: _agent(s), brief: briefOf(log, s), actions: BriefActions(answer: (_) {})),
          width: width,
        ));
        expect(tester.takeException(), isNull, reason: '$s at $width');
      }
    }
  });

  testWidgets('the demo: no session, its line only', (tester) async {
    final a = _agent(AgentStatus.error).copyWith(detail: 'API Error: 500');
    final answers = <AgentAnswer>[];
    await tester.pumpWidget(host(BriefView(agent: a, brief: briefOfAgent(a), actions: BriefActions(answer: answers.add))));
    expect(find.text('API Error: 500'), findsOneWidget);
    await tester.tap(find.text('Relancer'));
    expect(answers, [AgentAnswer.retry]);
  });

  group('SoundBoard', () {
    test('every cue has a known file or none', () {
      // The files of app/assets/sounds (README.md).
      const files = {'back', 'discord_close', 'discord_open', 'folder_close', 'folder_open', 'launch', 'navigate', 'retroachievements', 'select'};
      for (final cue in MikkyCue.values) {
        expect(soundFiles.containsKey(cue), isTrue, reason: '$cue');
        final f = soundFiles[cue];
        if (f != null) expect(files, contains(f));
      }
    });

    test('off, it is silent; on, never the same twice at once, never a crowd', () {
      final overlay = _FakeOverlay();
      var now = DateTime(2026);
      final settings = Settings(sound: false);
      final board = SoundBoard(overlay, settings, now: () => now);
      board.play(MikkyCue.finished);
      expect(overlay.played, isEmpty);

      settings.sound = true;
      board
        ..play(MikkyCue.finished)
        ..play(MikkyCue.finished);
      expect(overlay.played, ['retroachievements']);
      board
        ..play(MikkyCue.open)
        ..play(MikkyCue.back)
        ..play(MikkyCue.select);
      expect(overlay.played, ['retroachievements', 'discord_open', 'back']);
      now = now.add(const Duration(seconds: 1));
      board.play(MikkyCue.finished);
      expect(overlay.played.last, 'retroachievements');
    });
  });
}
