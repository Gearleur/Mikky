import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/ui/cards.dart';
import 'package:mikky/ui/tokens.dart';

void main() {
  testWidgets('pressing Non slides the white square to it, then answers on release', (tester) async {
    final said = <String>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: Center(
              child: AnswerBar(answers: [('Non', () => said.add('Non')), ('Oui', () => said.add('Oui'))]),
            ),
          ),
        ),
      ),
    );
    Rect square() => tester.getRect(find.byType(DecoratedBox).first);
    final oui = tester.getRect(find.text('Oui'));
    expect(square().center.dx, closeTo(oui.center.dx, 2));

    final gesture = await tester.startGesture(tester.getCenter(find.text('Non')));
    await tester.pumpAndSettle();
    final non = tester.getRect(find.text('Non'));
    expect(square().center.dx, closeTo(non.center.dx, 2));
    expect(said, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(said, ['Non']);
  });
}
