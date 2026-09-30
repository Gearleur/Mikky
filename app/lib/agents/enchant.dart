import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// « Ensorcelé » (user request, 2026-09-30): an agent stopped by its
/// subscription's limit goes on by itself when the limit lifts — Mikky
/// sends it a message to take the task up again. It stays under the spell
/// until a relaunch gets through: hit by the limit again, it waits for the
/// next reset. In memory for now: a restart of Mikky lifts every spell.
///
/// [everywhere]: « Relance automatique » for every agent (user request,
/// 2026-09-30), kept in the settings; [watch] casts the spells then.
class Enchantments extends ChangeNotifier {
  Enchantments._();

  static final instance = Enchantments._();

  bool _noticeDue = false;

  /// A spell cast while the screen is being built (a page opening) is told
  /// once the frame is done.
  @override
  void notifyListeners() {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      super.notifyListeners();
      return;
    }
    if (_noticeDue) return;
    _noticeDue = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _noticeDue = false;
      super.notifyListeners();
    });
  }

  /// What Mikky tells the agent when the limit lifts.
  static const resumeMessage = 'La limite de l’abonnement est levée : reprends la tâche là où tu t’étais arrêté.';

  /// Past the reset, a moment more, so the limit is really gone.
  static const _margin = Duration(minutes: 1);

  /// When the reset time is not known: try again after this long.
  static const _unknown = Duration(minutes: 30);

  /// Every agent stopped by a limit is put under the spell by itself.
  bool get everywhere => _everywhere;
  bool _everywhere = false;
  ValueChanged<bool>? _saveEverywhere;

  set everywhere(bool on) {
    if (on == _everywhere) return;
    _everywhere = on;
    _saveEverywhere?.call(on);
    notifyListeners();
    _check();
  }

  RealAgentSource? _source;
  StreamSubscription<void>? _sub;
  DateTime _watchedSince = DateTime.now();

  /// Limits the user took the spell off (the time the limit hit): the
  /// global mode leaves them alone.
  final _declined = <String, DateTime>{};

  /// Follows every agent of [source]: casts the spells in the global mode,
  /// casts them again when a relaunch meets the limit, lifts them when it
  /// gets through. [save] keeps the global mode's choice.
  void watch(RealAgentSource source, {required bool everywhere, required ValueChanged<bool> save}) {
    _sub?.cancel();
    _source = source;
    _everywhere = everywhere;
    _saveEverywhere = save;
    _watchedSince = DateTime.now();
    _sub = source.changes.listen((_) => _check());
    _check();
  }

  void _check() {
    final source = _source;
    if (source == null) return;
    final now = DateTime.now();
    for (final e in source.entries) {
      final log = e.log;
      Future<void> send(String t) => source.send(e.id, t);
      if (e.status == AgentStatus.rateLimited) {
        final at = log.lastEventAt ?? now;
        final resets = log.limitResetsAt;
        if (_sentAt.containsKey(e.id)) {
          limitedAgain(e.id, at, resets, send);
        } else if (_everywhere && !isOn(e.id) && _declined[e.id] != at) {
          // Only limits met while Mikky runs, or still in force: never
          // relaunch an old session from the history at start.
          if (at.isAfter(_watchedSince) || (resets != null && resets.isAfter(now))) enchant(e.id, resets, send);
        }
      } else if (_sentAt.containsKey(e.id) && !log.working && e.status != AgentStatus.rateLimited) {
        done(e.id);
      }
    }
  }

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
    final at = _source?.entry(id)?.log.lastEventAt;
    if (at != null) _declined[id] = at;
    _timers.remove(id)?.cancel();
    final waiting = _at.remove(id) != null;
    final sent = _sentAt.remove(id) != null;
    if (waiting || sent) notifyListeners();
  }
}
