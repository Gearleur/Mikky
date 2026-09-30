import 'dart:io';

import 'package:flutter/services.dart';

/// Every font family of pubspec.yaml, for tests that show real text.
Future<void> loadAppFonts() async {
  final families = <String, List<String>>{};
  String? family;
  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    final f = RegExp(r'^\s*- family: (.+)$').firstMatch(line);
    final a = RegExp(r'^\s*- asset: (assets/fonts/.+)$').firstMatch(line);
    if (f != null) family = f[1]!.trim();
    if (a != null && family != null) (families[family] ??= []).add(a[1]!.trim());
  }
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }
}
