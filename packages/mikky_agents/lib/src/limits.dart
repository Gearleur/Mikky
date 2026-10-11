import 'package:mikky_engine/mikky_engine.dart';

import 'agent_entry.dart';

/// The latest subscription limits seen for [provider] (in any of its
/// sessions), or null.
LimitsSeen? latestLimits(Iterable<AgentEntry> entries, AgentProvider provider, {required DateTime now}) {
  LimitsSeen? best;
  for (final e in entries) {
    if (e.provider != provider) continue;
    for (final l in [e.run?.log.limits, e.watched?.log.limits]) {
      if (l != null && (best == null || (l.at ?? DateTime(0)).isAfter(best.at ?? DateTime(0)))) best = l;
    }
  }
  if (best == null) return null;
  // Codex's last reading before it refuses can say 99 %: a turn stopped
  // by the limit since, not lifted yet, means the fullest window is full.
  final seen = best.at ?? DateTime(0);
  final stopped = entries.any((e) {
    final resets = e.log.limitResetsAt;
    final at = e.log.lastEventAt;
    return e.provider == provider && resets != null && resets.isAfter(now) && at != null && !at.isBefore(seen);
  });
  if (!stopped) return best;
  final short = best.short, long = best.long;
  final shortFull = long == null || (short != null && short.usedPercent >= long.usedPercent);
  LimitWindow? full(LimitWindow? w) => w == null ? null : LimitWindow(100, minutes: w.minutes, resetsAt: w.resetsAt);
  return LimitsSeen(
    short: shortFull ? full(short) : short,
    long: shortFull ? long : full(long),
    plan: best.plan,
    at: best.at,
  );
}
