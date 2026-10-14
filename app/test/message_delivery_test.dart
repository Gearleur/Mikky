import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_external_messages.dart';
import 'package:mikky/ui/content/message_delivery.dart';
import 'package:mikky/ui/content/messages.dart';
import 'package:mikky/ui/foundation/tokens.dart';

Widget page(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MikkyUiTheme(
      ui: MikkyUi.light,
      child: Center(child: SizedBox(width: 320, child: child)),
    ),
  ),
);

void main() {
  testWidgets('retry has one accessible label and Enter invokes it once', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var retries = 0;
      await tester.pumpWidget(
        page(MessageDelivery(text: 'Un message', state: MessageDeliveryState.failed, onRetry: () => retries++)),
      );
      expect(find.bySemanticsLabel('Réessayer'), findsOneWidget);
      Focus.of(tester.element(find.text('Réessayer'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(retries, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('uncertain delivery never offers retry even when a callback is supplied', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      page(MessageDelivery(text: 'Un message', state: MessageDeliveryState.unconfirmed, onRetry: () => retries++)),
    );
    expect(find.text('Réessayer'), findsNothing);
    expect(find.text('Envoi non confirmé'), findsOneWidget);
    expect(retries, 0);
  });

  testWidgets('retry stays in one bubble and cannot be sent again while sending', (tester) async {
    await tester.pumpWidget(page(const MessageRetryTrial()));
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(find.text('Envoi…'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
    expect(find.byType(ChatMessage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Envoyé'), findsOneWidget);
    expect(find.byType(ChatMessage), findsOneWidget);
    await tester.tap(find.text('Rejouer l’échec'));
    await tester.pump();
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
