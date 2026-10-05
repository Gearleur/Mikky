import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/session_views.dart';
import 'package:mikky/ui/thread_page.dart';
import 'package:mikky/ui/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// What keeps an agent's page light (2026-10-05): its thread builds only
/// what shows, and its finished turns are not built again.
void main() {
  Widget host(Widget child) => MediaQuery(
    data: const MediaQueryData(size: Size(700, 380), disableAnimations: true),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MikkyUiTheme(ui: MikkyUi.light, child: Overlay(initialEntries: [OverlayEntry(builder: (_) => child)])),
    ),
  );

  testWidgets('a long thread builds only what shows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 380));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var built = 0;
    await tester.pumpWidget(host(SizedBox(
      width: 700,
      height: 380,
      child: ThreadPage(
        back: () {},
        children: [for (var i = 0; i < 400; i++) Builder(builder: (_) {
          built++;
          return SizedBox(height: 40, child: Text('Message $i'));
        })],
      ),
    )));
    // About a screen of them, not 400.
    expect(built, lessThan(30));
  });

  testWidgets('finished turns are kept: the same widgets while the last goes on', (tester) async {
    final t0 = DateTime(2026, 10, 5, 14);
    final log = SessionLog();
    for (var i = 0; i < 3; i++) {
      log.applyAll([
        TurnStarted(at: t0),
        UserMessage('Tâche $i', at: t0),
        ToolCallEvent('t$i', kind: ToolKind.read, title: 'Lire a.dart', path: 'a.dart', status: ToolStatus.completed, at: t0),
        AgentMessage('Fait $i.', at: t0),
        TurnEnded(StopReason.endTurn, at: t0),
      ]);
    }
    log.applyAll([TurnStarted(at: t0), UserMessage('La suite', at: t0), const AgentMessage('Je regarde…')]);

    late BuildContext context;
    await tester.pumpWidget(host(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final cache = ThreadCache();
    final first = threadOf(context, log, cache: cache);
    // The last turn goes on: a new piece of its answer.
    log.apply(const AgentMessage(' Encore.'));
    final second = threadOf(context, log, cache: cache);

    // The first two turns (not the last finished one) are the very same
    // widgets; the answer at work is new (before the waiting dots).
    final kept = [for (var i = 0; i < first.length; i++) if (i < second.length && identical(first[i], second[i])) i];
    expect(kept.length, greaterThanOrEqualTo(8));
    expect(identical(first[first.length - 3], second[second.length - 3]), isFalse);
  });
}
