import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/fake_sessions.dart';
import 'package:mikky/side/session_cards.dart';
import 'package:mikky/side/session_views.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

void main() {
  testWidgets('a child limit appears in the still-open parent turn', (tester) async {
    final log = FakeSessions.subAgentLimited();
    expect(log.working, isTrue);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: Builder(
              builder: (context) => SingleChildScrollView(child: Column(children: threadOf(context, log))),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(LimitBlock), findsOneWidget);
    expect(log.statusAt(DateTime(2026, 9, 30, 14)), AgentStatus.rateLimited);
    expect(tester.takeException(), isNull);
  });
}
