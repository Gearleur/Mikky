import 'package:flutter/widgets.dart';

import 'island/island_painter.dart';
import 'island/island_view.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (settings, program) = await (Settings.load(), loadIslandProgram()).wait;
  // No app shell and no background: everything outside the island must stay
  // fully transparent.
  runApp(Directionality(
    textDirection: TextDirection.ltr,
    child: IslandView(settings: settings, program: program),
  ));
}
