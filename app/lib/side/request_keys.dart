import 'package:flutter/widgets.dart';

/// A key the island hears while it shows a request (2026-10-08): Y / N /
/// T (Toujours), 1 to 4 for the choices, Entrée. Échap stays the island's
/// (it folds without answering).
enum RequestKey {
  yes,
  no,
  always,
  enter,
  choice1,
  choice2,
  choice3,
  choice4;

  /// 0 to 3 for [choice1] to [choice4], else null.
  int? get choice => switch (this) {
    choice1 => 0,
    choice2 => 1,
    choice3 => 2,
    choice4 => 3,
    _ => null,
  };
}

/// From the island's keyboard to the request on screen: the request that
/// shows last listens ([listen]); [send] says whether it used the key.
class RequestKeys {
  final _listeners = <bool Function(RequestKey key)>[];

  void listen(bool Function(RequestKey key) listener) => _listeners.add(listener);
  void forget(bool Function(RequestKey key) listener) => _listeners.remove(listener);

  bool send(RequestKey key) {
    for (final l in _listeners.reversed) {
      if (l(key)) return true;
    }
    return false;
  }
}

/// The [RequestKeys] of the request pages below.
class RequestKeysScope extends InheritedWidget {
  const RequestKeysScope({super.key, required this.keys, required super.child});

  final RequestKeys keys;

  static RequestKeys? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RequestKeysScope>()?.keys;

  @override
  bool updateShouldNotify(RequestKeysScope old) => old.keys != keys;
}

/// Listens to the [RequestKeys] above while it is built.
mixin RequestKeysListener<T extends StatefulWidget> on State<T> {
  RequestKeys? _keys;

  /// Uses [key]: true if it did something with it.
  bool onRequestKey(RequestKey key);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keys = RequestKeysScope.maybeOf(context);
    if (keys == _keys) return;
    _keys?.forget(onRequestKey);
    _keys = keys?..listen(onRequestKey);
  }

  @override
  void dispose() {
    _keys?.forget(onRequestKey);
    super.dispose();
  }
}
