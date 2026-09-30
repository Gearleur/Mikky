/// When a subscription limit lifts, read from what the agent said when it
/// stopped (user request, 2026-09-30: a proper « limite atteinte » state).
/// [seen] is when the message came: times of day are taken after it,
/// durations from it. Null when the message does not say.
///
/// Claude: `Claude AI usage limit reached|1759248000` (seconds), or
/// `5-hour limit reached ∙ resets 5pm`, `resets 5:30pm (Europe/Paris)`.
/// Codex: `try again at 5:10 PM`, `try again in 2 hours 13 minutes`.
DateTime? limitResetOf(String message, DateTime seen) {
  final epoch = RegExp(r'\|(\d{9,11})\b').firstMatch(message);
  if (epoch != null) return DateTime.fromMillisecondsSinceEpoch(int.parse(epoch[1]!) * 1000);

  final text = message.toLowerCase();
  final inHours = RegExp(r'in\s+(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:in(?:ute)?s?)?)?').allMatches(text);
  for (final m in inHours) {
    final h = int.tryParse(m[1] ?? ''), min = int.tryParse(m[2] ?? '');
    if (h == null && min == null) continue;
    return seen.add(Duration(hours: h ?? 0, minutes: min ?? 0));
  }

  final at = RegExp(r'(?:resets?|again at|at)\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b').firstMatch(text);
  if (at != null) {
    var hour = int.parse(at[1]!);
    final minute = int.tryParse(at[2] ?? '') ?? 0;
    final half = at[3];
    if (half == null && at[2] == null) return null;
    if (half == 'pm' && hour < 12) hour += 12;
    if (half == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    var when = DateTime(seen.year, seen.month, seen.day, hour, minute);
    if (!when.isAfter(seen)) when = when.add(const Duration(days: 1));
    return when;
  }
  return null;
}

/// « Limite atteinte · reprend à 17 h 10 », or « Limite atteinte ».
String limitLine(DateTime? resetsAt) {
  if (resetsAt == null) return 'Limite atteinte';
  final t = resetsAt.toLocal();
  final time = t.minute == 0 ? '${t.hour} h' : '${t.hour} h ${t.minute.toString().padLeft(2, '0')}';
  return 'Limite atteinte · reprend à $time';
}
