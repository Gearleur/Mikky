import 'package:flutter/widgets.dart';

import 'island/j0_island.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // No app shell and no background: everything outside the island must stay
  // fully transparent.
  runApp(const Directionality(textDirection: TextDirection.ltr, child: J0Island()));
}
