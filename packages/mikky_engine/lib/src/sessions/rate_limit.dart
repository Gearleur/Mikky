/// When a subscription limit lifts, read from what the agent said when it
/// stopped (user request, 2026-09-30: a proper « limite atteinte » state).
/// [seen] is when the message came: times of day are taken after it,
/// durations from it. Null when the message does not say.
///
/// Claude: `Claude AI usage limit reached|1759248000` (seconds), or
/// `5-hour limit reached ∙ resets 5pm`, `resets 5:30pm (Europe/Paris)`.
/// Codex: `try again at 5:10 PM`, `try again in 2 hours 13 minutes`,
/// `try again at Oct 5th, 2026 9:47 AM` (a weekly limit, 2026-10-02).
DateTime? limitResetOf(String message, DateTime seen) {
  final epoch = RegExp(r'\|(\d{9,11})\b').firstMatch(message);
  if (epoch != null) return DateTime.fromMillisecondsSinceEpoch(int.parse(epoch[1]!) * 1000);

  final text = message.toLowerCase();
  final dated = RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s*(\d{4})?,?\s+(\d{1,2}):(\d{2})\s*(am|pm)?').firstMatch(text);
  if (dated != null) {
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    var hour = int.parse(dated[4]!);
    final half = dated[6];
    if (half == 'pm' && hour < 12) hour += 12;
    if (half == 'am' && hour == 12) hour = 0;
    final year = int.tryParse(dated[3] ?? '') ?? seen.year;
    final when = DateTime(year, months.indexOf(dated[1]!) + 1, int.parse(dated[2]!), hour, int.parse(dated[5]!));
    // No year said and already past: next year's.
    return dated[3] == null && !when.isAfter(seen) ? DateTime(year + 1, when.month, when.day, when.hour, when.minute) : when;
  }
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

/// « Limite atteinte · reprend à 17 h 10 », or « Limite atteinte ». Another
/// day than [seen] (when it stopped): « reprend le 5 oct. à 9 h 47 ».
String limitLine(DateTime? resetsAt, {DateTime? seen}) =>
    resetsAt == null ? 'Limite atteinte' : 'Limite atteinte · ${limitWhen(resetsAt, seen: seen)}';

/// « reprend à 17 h 10 », « reprend demain à 9 h », « reprend le 5 oct. à
/// 9 h 47 » (days counted from [seen]; none: the time only).
String limitWhen(DateTime resetsAt, {DateTime? seen}) {
  final t = resetsAt.toLocal();
  final time = t.minute == 0 ? '${t.hour} h' : '${t.hour} h ${t.minute.toString().padLeft(2, '0')}';
  final s = seen?.toLocal();
  if (s != null && (s.year != t.year || s.month != t.month || s.day != t.day)) {
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    final tomorrow = DateTime(s.year, s.month, s.day + 1);
    if (t.year == tomorrow.year && t.month == tomorrow.month && t.day == tomorrow.day) return 'reprend demain à $time';
    return 'reprend le ${t.day} ${months[t.month - 1]} à $time';
  }
  return 'reprend à $time';
}
