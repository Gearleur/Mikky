import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/session_views.dart';
import 'package:mikky/ui/content/side.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../../packages/mikky_engine/test/support/readers/acp_reader.dart';
import 'load_fonts.dart';

/// Replays an ACP recording; [until] stops it midway (an agent at work).
SessionLog _replay(String name, {int? until}) {
  final reader = AcpReader();
  final log = SessionLog();
  final start = DateTime.utc(2026, 9, 29, 12);
  final lines = File('../packages/mikky_engine/test/fixtures/acp/$name')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  for (final l in until == null ? lines : lines.take(until)) {
    final j = (jsonDecode(l) as Map).cast<String, dynamic>();
    log.applyAll(
      reader.read(
        (j['msg'] as Map).cast<String, dynamic>(),
        outgoing: j['dir'] == 'out',
        at: start.add(Duration(milliseconds: j['t'] as int)),
      ),
    );
  }
  return log;
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SideFrame(
    // Tall enough to see a whole task and the answer under it.
    height: 1060,
    child: Stack(
      children: [
        SideHead(title: title, small: true, leading: const SizedBox(width: 34, height: 34)),
        Positioned.fill(
          top: 68,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    ),
  );
}

/// The agent page's thread built from real sessions recorded in the A0
/// probe: while the agent works, and once it is done. Update
/// with `flutter test --update-goldens test/side_pages_test.dart`, then look.
void main() {
  setUpAll(loadAppFonts);

  for (final (name, ui) in [('light', MikkyUi.light), ('dark', MikkyUi.dark)]) {
    testWidgets('agent page views, $name', (tester) async {
      const size = Size(740, 1100);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // At work: the WSL run with a plan, stopped while it waits for a yes.
      final working = _replay('claude_wsl_plan.jsonl', until: 60);
      final done = _replay('claude_windows_steer_deny.jsonl');
      const board = Key('board');
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: size, disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MikkyUiTheme(
              ui: ui,
              child: RepaintBoundary(
                key: board,
                child: ColoredBox(
                  color: ui.board,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Builder(
                      builder: (context) => Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Page(title: 'Au travail', children: threadOf(context, working)),
                          const SizedBox(width: 30),
                          _Page(title: 'Fini', children: threadOf(context, done)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await expectLater(find.byKey(board), matchesGoldenFile('goldens/side_pages_$name.png'));
    });
  }
}
