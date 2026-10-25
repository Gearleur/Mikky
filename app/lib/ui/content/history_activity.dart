import 'package:flutter/widgets.dart';

import '../foundation/status.dart';
import '../pixels/pixel_fx.dart';

/// The same blue thinking star as the rest of the app.
class HistoryActivity extends StatelessWidget {
  const HistoryActivity({super.key});

  @override
  Widget build(BuildContext context) =>
      Semantics(label: 'Agent en cours de travail', child: const StatusFx(UiStatus.working, size: 11));
}
