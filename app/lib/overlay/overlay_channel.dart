import 'package:flutter/services.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// Bridge to the native overlay window (`windows/runner/flutter_window.cpp`).
///
/// All coordinates are logical pixels relative to the window's top-left
/// corner. The window is glued to the top or the right edge of the primary
/// screen (see [setPlacement]).
class OverlayChannel {
  OverlayChannel() {
    _channel.setMethodCallHandler(_handle);
  }

  static const _channel = MethodChannel('mikky/overlay');

  /// Global cursor position, at most 60 times per second, only when it moves.
  /// It can be outside the window.
  void Function(Offset cursor)? onCursor;

  /// A mouse button went down outside the island and outside Mikky's own
  /// menus and dialogs (the click goes on to the app below).
  void Function()? onOutsideClick;

  /// The icon in the notification area: left click, right click, and a
  /// click on a notification.
  void Function()? onTrayClick;
  void Function()? onTrayMenu;
  void Function()? onNotificationClick;

  /// A global shortcut set by [setHotkeys] was pressed: its id.
  void Function(int id)? onHotkey;

  Rect? _hitRect;

  Future<void> _handle(MethodCall call) async {
    if (call.method == 'outsideClick') {
      onOutsideClick?.call();
    } else if (call.method == 'trayClick') {
      onTrayClick?.call();
    } else if (call.method == 'trayMenu') {
      onTrayMenu?.call();
    } else if (call.method == 'notificationClick') {
      onNotificationClick?.call();
    } else if (call.method == 'hotkey') {
      onHotkey?.call(call.arguments as int);
    } else if (call.method == 'cursor') {
      final args = call.arguments as List<Object?>;
      onCursor?.call(Offset((args[0]! as num).toDouble(), (args[1]! as num).toDouble()));
    }
  }

  /// Glues the window to [edge] of the primary screen, with [size] in
  /// logical pixels. Clicks go through until the next [setHitRect].
  Future<void> setPlacement(IslandEdge edge, Size size) async {
    _hitRect = Rect.zero;
    await _channel.invokeMethod<void>('setPlacement', [edge.name, size.width, size.height]);
  }

  /// The only area that receives clicks; everywhere else they go through to
  /// the windows below. [Rect.zero] makes the whole window click-through.
  void setHitRect(Rect rect) {
    if (rect == _hitRect) return;
    _hitRect = rect;
    _channel.invokeMethod<void>('setHitRect', [rect.left, rect.top, rect.width, rect.height]);
  }

  /// Shows a native context menu at the cursor. Returns the chosen item's
  /// id, or null if the menu was dismissed.
  Future<int?> showMenu(List<MenuEntry> entries) async {
    final chosen = await _channel.invokeMethod<int>('showMenu', [
      for (final e in entries) [e.id, e.label, e.checked],
    ]);
    return chosen == null || chosen == 0 ? null : chosen;
  }

  /// Takes the keyboard focus, for Escape and the N / Y shortcuts. Only
  /// right after the user clicked the island.
  void activate() => _channel.invokeMethod<void>('activate');

  /// Windows' folder picker, on top of the island. Null if cancelled.
  /// WSL folders are reachable through `\\wsl.localhost\…`.
  Future<String?> pickFolder(String title) => _channel.invokeMethod<String>('pickFolder', title);

  /// A Windows notification (from the icon in the notification area).
  void notify(String title, String body) => _channel.invokeMethod<void>('notify', [title, body]);

  /// Plays `assets/sounds/<name>.mp3` at [volume] (0..1); silent if the
  /// file is missing.
  void playSound(String name, double volume) => _channel.invokeMethod<void>('playSound', [name, volume]);

  /// Opens these sounds ahead, so their first play is on time.
  void preloadSounds(Iterable<String> names) => _channel.invokeMethod<void>('preloadSounds', names.toList());

  /// Global shortcuts, replacing the previous ones: (id, modifiers, virtual
  /// key) with Windows' MOD_ALT 1, MOD_CONTROL 2, MOD_SHIFT 4, MOD_WIN 8.
  /// Returns the ids Windows refused (taken by another app).
  Future<List<int>> setHotkeys(List<(int, int, int)> keys) async {
    final refused = await _channel.invokeMethod<List<Object?>>('setHotkeys', [
      for (final (id, mods, key) in keys) [id, mods, key],
    ]);
    return [for (final id in refused ?? const []) id! as int];
  }

  void quit() => _channel.invokeMethod<void>('quit');
}

/// One line of a native menu. Id 0 is a separator.
class MenuEntry {
  const MenuEntry(this.id, this.label, {this.checked = false}) : assert(id > 0);
  const MenuEntry.separator()
      : id = 0,
        label = '',
        checked = false;

  final int id;
  final String label;
  final bool checked;
}
