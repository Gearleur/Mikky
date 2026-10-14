import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/canvas.dart';
import 'package:mikky/side/agent_page.dart';
import 'package:mikky/ui/content/messages.dart';
import 'package:mikky/ui/controls/field.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

void main() {
  testWidgets('external Claude keeps its field and shows a queued message once, before and after the transcript echo', (
    tester,
  ) async {
    final log = SessionLog()..apply(const TurnStarted());
    final message = ExternalMessage(
      id: 'mikky-one',
      sessionId: 's',
      text: 'Ajoute aussi les tests',
      at: DateTime(2026),
    );
    Future<void> page() => tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: SizedBox(
              width: 344,
              height: 520,
              child: OwnOverlay(
                child: AgentPageView(
                  model: AgentPageModel(
                    id: 's',
                    log: log,
                    status: AgentStatus.working,
                    external: true,
                    live: false,
                    canQueueExternal: true,
                    messages: [message],
                  ),
                  actions: AgentPageActions(back: () {}, send: (_) async {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await page();
    expect(find.byType(Composer), findsOneWidget);
    expect(tester.widget<Composer>(find.byType(Composer)).placeholder, 'Arrive à son prochain outil…');
    expect(find.text('En attente du prochain outil'), findsOneWidget);
    log.apply(const UserMessage('Ajoute aussi les tests', queued: true, messageId: 'mikky-one'));
    log.apply(const UserMessage('Ajoute aussi les tests', queued: true, messageId: 'mikky-one'));
    log.apply(const AgentMessage('D’accord.'));
    log.apply(const TurnEnded(StopReason.endTurn));
    await page();
    await tester.pump();
    final bubbles = tester
        .widgetList<ChatMessage>(find.byType(ChatMessage))
        .where((m) => m.me && m.text == message.text);
    expect(bubbles, hasLength(1));
    expect(bubbles.single.meta, 'Message transmis');
    expect(log.items.whereType<UserItem>(), hasLength(1));
  });
}
