import 'package:flutter/widgets.dart';

import 'island/island_painter.dart';
import 'island/island_view.dart';
import 'overlay/overlay_channel.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final overlay = OverlayChannel();
  final (settings, program) = await (Settings.load(), loadIslandProgram()).wait;
  // Before the first frame: the window only shows up once it is in place.
  await overlay.setPlacement(settings.edge, windowSizeFor(settings.edge));
  // No app shell and no background: everything outside the island must stay
  // fully transparent.
  runApp(Directionality(
    textDirection: TextDirection.ltr,
    child: IslandView(overlay: overlay, settings: settings, program: program),
  ));
}
