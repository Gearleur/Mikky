import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

// What the window says about a session, in words: times, names, figures.

/// « à l'instant », « il y a 4 min », « hier »…
String ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'à l’instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24 && t.day == now.day) return 'il y a ${d.inHours} h';
  final yesterday = now.subtract(const Duration(days: 1));
  if (t.year == yesterday.year && t.month == yesterday.month && t.day == yesterday.day) return 'hier';
  return 'le ${t.day}/${t.month}';
}

String clockTime(DateTime t) {
  final l = t.toLocal();
  return '${l.hour}:${l.minute.toString().padLeft(2, '0')}';
}

/// « 17 h », « 17 h 05 ».
String hourText(DateTime t) {
  final l = t.toLocal();
  return l.minute == 0 ? '${l.hour} h' : '${l.hour} h ${l.minute.toString().padLeft(2, '0')}';
}

/// « Claude », « Codex · WSL ».
String whoOf(AgentEntry e) => '${e.provider == AgentProvider.claude ? 'Claude' : 'Codex'}${e.host == AgentHost.wsl ? ' · WSL' : ''}';

String folderName(String? path) =>
    path == null ? '' : path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ?? path;

/// What a permission request asks, in words.
String askLabel(SessionLog log) {
  final asked = log.pending.firstOrNull;
  if (asked == null) return 'Attend ton feu vert';
  final tool = log.items.whereType<ToolItem>().where((t) => t.id == asked.toolCallId).firstOrNull;
  return switch (tool?.kind) {
    ToolKind.execute => 'Veut lancer une commande',
    ToolKind.edit => 'Veut modifier un fichier',
    ToolKind.delete => 'Veut supprimer un fichier',
    ToolKind.move => 'Veut déplacer un fichier',
    ToolKind.fetch => 'Veut aller sur internet',
    _ => 'Attend ton feu vert',
  };
}

/// 950, « 12,3 k », « 1,2 M ».
String formatTokens(int n) {
  String one(double v) => v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.', ',').replaceAll(',0', '');
  if (n < 1000) return '$n';
  if (n < 1000000) return '${one(n / 1000)} k';
  return '${one(n / 1000000)} M';
}

/// « Contexte 34 % · 12,3 k jetons » for an agent's page; empty if unknown.
String usageLine(SessionLog log) {
  final parts = <String>[
    if (log.contextSize != null && log.contextUsed != null) 'Contexte ${(100 * log.contextUsed! / log.contextSize!).round()} %',
    if (log.tokens > 0) '${formatTokens(log.tokens)} jetons',
  ];
  return parts.join(' · ');
}

/// « 6 % des 5 h, repart à 18:58 · 10 % de la semaine ».
String limitsLine(LimitsSeen l) {
  String window(LimitWindow w) {
    final span = switch (w.minutes) {
      300 => 'des 5 h',
      10080 => 'de la semaine',
      final m when m % 1440 == 0 => 'des ${m ~/ 1440} j',
      final m when m % 60 == 0 => 'des ${m ~/ 60} h',
      final m => 'des $m min',
    };
    final reset = w.resetsAt;
    final back = reset == null || w.minutes > 1440 ? '' : ', repart à ${clockTime(reset)}';
    return '${w.usedPercent.round()} % $span$back';
  }

  return [if (l.short != null) window(l.short!), if (l.long != null) window(l.long!)].join(' · ');
}
