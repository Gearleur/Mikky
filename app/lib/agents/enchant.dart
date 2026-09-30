import 'dart:async';

import 'package:flutter/foundation.dart';

/// « Ensorcelé » (user request, 2026-09-30): an agent stopped by its
/// subscription's limit goes on by itself when the limit lifts — Mikky
/// sends it a message to take the task up again. It stays under the spell
/// until a relaunch gets through: hit by the limit again, it waits for the
/// next reset. In memory for now: a restart of Mikky lifts every spell.
class Enchantments extends ChangeNotifier {
  Enchantments._();

  static final instance = Enchantments._();

  /// What Mikky tells the agent when the limit lifts.
  static const resumeMessage = 'La limite de l’abonnement est levée : reprends la tâche là où tu t’étais arrêté.';

  /// Past the reset, a moment more, so the limit is really gone.
  static const _margin = Duration(minutes: 1);

  /// When the reset time is not known: try again after this long.
  static const _unknown = Duration(minutes: 30);

  final _timers = <String, Timer>{};
  final _at = <String, DateTime>{};
  final _sentAt = <String, DateTime>{};

  /// When agent [id] is relaunched, or null if it is not under the spell
  /// (or its relaunch was just sent).
  DateTime? relaunchAt(String id) => _at[id];

  /// Under the spell: waiting for its relaunch, or relaunched and not yet
  /// through.
  bool isOn(String id) => _at.containsKey(id) || _sentAt.containsKey(id);

  /// Relaunch [id] once its limit lifts at [resetsAt] (unknown: in 30 min),
  /// with [send].
  void enchant(String id, DateTime? resetsAt, Future<void> Function(String text) send, {DateTime? now}) {
    _timers.remove(id)?.cancel();
    _sentAt.remove(id);
    final from = now ?? DateTime.now();
    var when = (resetsAt ?? from.add(_unknown)).add(_margin);
    if (!when.isAfter(from)) when = from.add(const Duration(seconds: 5));
    _at[id] = when;
    _timers[id] = Timer(when.difference(from), () {
      _timers.remove(id);
      _at.remove(id);
      _sentAt[id] = DateTime.now();
      notifyListeners();
      send(resumeMessage);
    });
    notifyListeners();
  }

  /// The relaunch sent at the time was stopped by the limit again (reset
  /// at [resetsAt]): wait for the next one. Does nothing if [id] is not
  /// waiting on a relaunch sent before [limitAt].
  void limitedAgain(String id, DateTime limitAt, DateTime? resetsAt, Future<void> Function(String text) send) {
    final sent = _sentAt[id];
    if (sent == null || limitAt.isBefore(sent)) return;
    enchant(id, resetsAt, send);
  }

  /// The relaunch went through: the spell is over.
  void done(String id) {
    if (_sentAt.remove(id) != null) notifyListeners();
  }

  void cancel(String id) {
    _timers.remove(id)?.cancel();
    final waiting = _at.remove(id) != null;
    final sent = _sentAt.remove(id) != null;
    if (waiting || sent) notifyListeners();
  }
}
