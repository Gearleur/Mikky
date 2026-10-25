import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_notch_journeys.dart';
import 'package:mikky/home/home_view.dart';
import 'package:mikky/side/agent_page.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the source journey resumes the same conversation and opens its real thread', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xffffffff),
        builder: (context, _) => const MikkyUiScope(
          ui: MikkyUi.light,
          child: Align(alignment: Alignment.topLeft, child: NotchJourney()),
        ),
      ),
    );
    await tester.pump();
    HomeView home() => tester.widget<HomeView>(find.byType(HomeView));
    expect(home().watched!.status.isBusy, isTrue);
    final log = home().watched!.log;
    await tester.tap(find.text('Étape suivante'));
    await tester.pumpAndSettle();
    expect(home().watched!.status, AgentStatus.rateLimited);
    await tester.tap(find.text('Voir le fil'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentPageView), findsOneWidget);
    await tester.tap(find.text('Étape suivante'));
    await tester.pumpAndSettle();
    expect(tester.widget<AgentPageView>(find.byType(AgentPageView)).model.log, same(log));
    expect(log.statusAt(log.lastEventAt!).isBusy, isTrue);
    expect(log.limitSource, isNull);
    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Étape suivante'));
    await tester.pumpAndSettle();
    expect(home().watched!.status, AgentStatus.finished);
    await tester.tap(find.text('Rejouer'));
    await tester.pumpAndSettle();
    expect(home().watched!.status.isBusy, isTrue);
    expect(tester.takeException(), isNull);
  });
}
