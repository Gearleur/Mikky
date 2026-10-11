import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../overlay/overlay_channel.dart';

/// The global shortcuts, all with Ctrl + Alt: A to the request waiting,
/// Espace to open or close the island, M for the sounds.
enum IslandHotkey {
  alert(1, 0x41),
  toggle(2, 0x20),
  mute(3, 0x4D);

  const IslandHotkey(this.id, this.virtualKey);

  /// Its id for [OverlayChannel.setHotkeys] and [OverlayChannel.onHotkey].
  final int id;

  /// Windows' virtual key code.
  final int virtualKey;

  /// MOD_CONTROL | MOD_ALT.
  static const _ctrlAlt = 2 | 1;

  static IslandHotkey? byId(int id) => values.where((k) => k.id == id).firstOrNull;

  /// Registers every shortcut, or none when [enabled] is off. Windows
  /// refuses one taken by another app: it is then left out, said once in
  /// the console.
  static Future<void> register(OverlayChannel overlay, {required bool enabled}) async {
    final keys = [
      if (enabled)
        for (final k in values) (k.id, _ctrlAlt, k.virtualKey),
    ];
    try {
      final refused = await overlay.setHotkeys(keys);
      if (refused.isNotEmpty) debugPrint('mikky: shortcuts taken by another app: $refused');
    } on MissingPluginException {
      // Tests and the boards: no native window.
    }
  }
}
