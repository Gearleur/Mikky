import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/home_screen.dart';
import 'package:mikky/ui/app_tile.dart';
import 'package:mikky/ui/pixel_fx.dart';
import 'package:mikky/ui/status.dart';
import 'package:mikky/ui/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

void main() {
  group('an app\'s state on its tile', () {
    test('every state of an agent', () {
      expect(appStatus(AgentStatus.working, AgentStatus.working), UiStatus.working);
      expect(appStatus(AgentStatus.thinking, AgentStatus.thinking), UiStatus.working);
      expect(appStatus(AgentStatus.searching, AgentStatus.searching), UiStatus.working);
      expect(appStatus(AgentStatus.approval, AgentStatus.approval), UiStatus.approval);
      expect(appStatus(AgentStatus.question, AgentStatus.question), UiStatus.approval);
      expect(appStatus(AgentStatus.error, AgentStatus.error), UiStatus.error);
      expect(appStatus(AgentStatus.rateLimited, AgentStatus.rateLimited), UiStatus.limited);
      expect(appStatus(AgentStatus.finished, AgentStatus.finished), UiStatus.finished);
    });

    test('a turn over (idle) is finished, green — not a blank pause', () {
      expect(appStatus(AgentStatus.idle, AgentStatus.idle), UiStatus.finished);
    });

    test('a limit or an error the user settled is finished', () {
      expect(appStatus(AgentStatus.rateLimited, AgentStatus.finished), UiStatus.finished);
      expect(appStatus(AgentStatus.error, AgentStatus.finished), UiStatus.finished);
    });

    test('paused by the user: nothing on the tile', () {
      expect(appStatus(AgentStatus.paused, AgentStatus.paused), isNull);
    });
  });

  testWidgets('each state draws its pixels in its color on the tile', (tester) async {
    for (final ui in [MikkyUi.light, MikkyUi.dark]) {
      for (final s in [UiStatus.working, UiStatus.approval, UiStatus.finished, UiStatus.error, UiStatus.limited]) {
        await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MikkyUiTheme(ui: ui, child: Center(child: AppTile(size: 64, status: s))),
          ),
        ));
        expect(find.byType(StatusFx), findsOneWidget, reason: '$s');
        final fx = tester.widget<PixelFx>(find.byType(PixelFx));
        expect(fx.palette.name, PixelFxPalette.of(s, ui).name, reason: '$s');
        // Something is drawn in the badge (not an empty square).
        expect(find.descendant(of: find.byType(PixelFx), matching: find.byType(CustomPaint)), findsWidgets, reason: '$s');
      }
    }
  });
}
