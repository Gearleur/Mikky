import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/agents/agents_service.dart';
import 'package:mikky/home/home_layout.dart';
import 'package:mikky/home/home_view.dart';
import 'package:mikky/settings.dart';
import 'package:mikky/settings/settings_button.dart';
import 'package:mikky/settings/settings_controller.dart';
import 'package:mikky/settings/settings_sheet.dart';
import 'package:mikky/settings/settings_top_view.dart';
import 'package:mikky/theme.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky/ui/overlays/sheet.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'load_fonts.dart';

class _Service extends AgentsService {
  _Service(File file) : super(clock: () => 0, store: AgentStore(file), connectBackend: () async => null) {
    backend = BackendState.online;
  }
  Completer<void>? startup;

  @override
  Future<Map<String, Object?>> hooksStatus(AgentProvider tool) async => {
    'installed': tool == AgentProvider.claude,
    'upToDate': true,
  };

  @override
  Future<void> setAutostart(bool enabled) async {
    await startup?.future;
    autostartEnabled = enabled;
    notifyListeners();
  }
}

Widget host(Widget child) => WidgetsApp(
  color: MikkyUi.light.island,
  builder: (_, _) => MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MikkyUiScope(
      ui: MikkyUi.light,
      child: Center(child: child),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('settings on the home are an icon at the bottom left with no visible label', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var opened = 0;
      await tester.pumpWidget(host(HomeView(animate: false, onSettings: (_) => opened++)));
      expect(find.text('Paramètres'), findsNothing);
      expect(find.bySemanticsLabel('Paramètres'), findsOneWidget);
      final button = tester.getRect(find.byType(SettingsButton));
      expect(button.size, const Size(24, 24));
      expect(button.left - tester.getRect(find.byType(HomeView)).left, HomeLayout.top.side);
      await tester.tap(find.bySemanticsLabel('Paramètres'));
      expect(opened, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('live sheet shares preferences, reads hooks and waits for startup acknowledgment', (tester) async {
    final semantics = tester.ensureSemantics();
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('mikky-settings-live-')))!;
    final service = _Service(File('${dir.path}/agents.json'));
    final written = <Settings>[];
    final c = SettingsController(Settings(), write: (snapshot) async => written.add(snapshot));
    try {
      await tester.pumpWidget(
        host(
          HomeView(
            animate: false,
            onSettings: (within) => unawaited(
              showSettingsSheet(
                within,
                controller: c,
                service: service,
                top: true,
                openHooks: (_) {},
                diagnostics: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Paramètres'));
      await tester.pumpAndSettle();
      expect(find.text('Activés'), findsOneWidget);
      expect(find.text('Absents'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Thème Sombre'));
      await tester.pump();
      expect(c.settings.theme, ThemeChoice.dark);
      expect(MikkyUi.of(tester.element(find.byType(SheetScene))).isLight, isFalse);
      service.startup = Completer<void>();
      await tester.tap(find.bySemanticsLabel('Au démarrage'));
      await tester.pump();
      expect(service.autostartEnabled, isFalse);
      expect(tester.widget<SettingsTopView>(find.byType(SettingsTopView)).autostart, isFalse);
      service.startup!.complete();
      await tester.pumpAndSettle();
      expect(service.autostartEnabled, isTrue);
      await tester.tap(find.bySemanticsLabel('Position À droite'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSheet), findsNothing);
      expect(c.settings.edge, IslandEdge.right);
      final saving = c.flush();
      await tester.pump();
      await saving;
      expect(written.last.edge, IslandEdge.right);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.runAsync(() async {
        await service.shutdown();
        service.dispose();
        await dir.delete(recursive: true);
      });
      semantics.dispose();
    }
  });
}
