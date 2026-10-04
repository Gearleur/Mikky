import '../agents/agent.dart';
import 'session_event.dart';
import 'session_log.dart';

/// Lines added and removed by a file change.
class DiffStat {
  const DiffStat(this.added, this.removed, {this.tooLarge = false});

  final int added, removed;

  /// Too big to compare line by line: counts of lines kept or not, in any
  /// order (still right for a new file).
  final bool tooLarge;

  /// « +12 −3 ».
  String get label => '+$added −$removed';

  @override
  bool operator ==(Object other) => other is DiffStat && other.added == added && other.removed == removed;

  @override
  int get hashCode => Object.hash(added, removed);

  @override
  String toString() => label;
}

/// Above this many lines in both texts together, no line-by-line
/// comparison (Mochi's limit).
const _maxDiffLines = 4000;

/// How many lines [d] adds and removes: the longest common run of lines is
/// kept, the rest changed. Never reads the disk.
DiffStat diffStat(FileDiff d) {
  final after = _lines(d.newText);
  final before = d.oldText == null ? const <String>[] : _lines(d.oldText!);
  if (before.isEmpty) return DiffStat(after.length, 0);
  if (before.length + after.length > _maxDiffLines) {
    // Lines of [before] missing from [after], and the other way round.
    final left = <String, int>{};
    for (final l in before) {
      left[l] = (left[l] ?? 0) + 1;
    }
    var added = 0;
    for (final l in after) {
      final n = left[l] ?? 0;
      if (n > 0) {
        left[l] = n - 1;
      } else {
        added++;
      }
    }
    final removed = left.values.fold(0, (a, b) => a + b);
    return DiffStat(added, removed, tooLarge: true);
  }
  // Same start and same end are common: compare only the middle.
  var start = 0;
  while (start < before.length && start < after.length && before[start] == after[start]) {
    start++;
  }
  var endB = before.length, endA = after.length;
  while (endB > start && endA > start && before[endB - 1] == after[endA - 1]) {
    endB--;
    endA--;
  }
  final b = before.sublist(start, endB), a = after.sublist(start, endA);
  final common = _lcs(b, a);
  return DiffStat(a.length - common, b.length - common);
}

List<String> _lines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Length of the longest common subsequence, in two rows of memory.
int _lcs(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var prev = List<int>.filled(b.length + 1, 0);
  var row = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      row[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : (prev[j] > row[j - 1] ? prev[j] : row[j - 1]);
    }
    final t = prev;
    prev = row;
    row = t;
  }
  return prev[b.length];
}

/// One thing the agent did: « Edit main.dart +3 −1 », « Bash cargo test ».
class ActivityLine {
  const ActivityLine({required this.kind, required this.text, this.diff, this.running = false, this.failed = false});

  final ToolKind kind;
  final String text;
  final DiffStat? diff;

  /// Still going on.
  final bool running;
  final bool failed;

  @override
  String toString() => '$kind $text${diff == null ? '' : ' $diff'}';
}

/// The last [max] things the agent did in its latest turn, oldest first.
List<ActivityLine> activityOf(SessionLog log, {int max = 4}) {
  final turns = log.turns;
  if (turns.isEmpty) return const [];
  final items = log.items;
  final turn = turns.last;
  final out = <ActivityLine>[];
  for (var i = (turn.end ?? items.length) - 1; i >= turn.start && out.length < max; i--) {
    final item = items[i];
    if (item is! ToolItem) continue;
    out.add(_lineOf(item));
  }
  return out.reversed.toList();
}

ActivityLine _lineOf(ToolItem t) {
  final diff = t.diff;
  final name = _fileName(diff?.path ?? t.path);
  final text = switch (t.kind) {
    ToolKind.edit || ToolKind.delete || ToolKind.move when name != null => '${_verb(t)} $name',
    ToolKind.execute when (t.command ?? '').isNotEmpty => _one(t.command!),
    _ => _one(t.title.isNotEmpty ? t.title : (t.name ?? t.kind.name)),
  };
  return ActivityLine(
    kind: t.kind,
    text: text,
    diff: diff == null ? null : diffStat(diff),
    running: t.active,
    failed: t.status == ToolStatus.failed,
  );
}

String _verb(ToolItem t) => switch (t.kind) {
  ToolKind.delete => 'Supprime',
  ToolKind.move => 'Déplace',
  _ => t.diff?.oldText == null ? 'Crée' : 'Modifie',
};

String? _fileName(String? path) {
  if (path == null || path.isEmpty) return null;
  return path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ?? path;
}

/// What an agent wants from the user, or what happened to it.
enum BriefKind { approval, question, error, rateLimited, finished, working, idle }

BriefKind briefKindOf(AgentStatus s) => switch (s) {
  AgentStatus.approval => BriefKind.approval,
  AgentStatus.question => BriefKind.question,
  AgentStatus.error => BriefKind.error,
  AgentStatus.rateLimited => BriefKind.rateLimited,
  AgentStatus.finished => BriefKind.finished,
  AgentStatus.working || AgentStatus.thinking || AgentStatus.searching => BriefKind.working,
  AgentStatus.paused || AgentStatus.idle => BriefKind.idle,
};

/// A file the agent changed in its turn, with how much.
typedef FileChange = ({String name, DiffStat diff});

/// Everything Mikky brings with a request (2026-10-04, « que ce soit
/// Mikky qui l'amène avec le contexte de la tâche »): which task, where it
/// stands, what the agent just said and did, then what it asks.
class TaskBrief {
  const TaskBrief({
    required this.kind,
    this.task,
    this.step,
    this.said,
    this.request = '',
    this.requestTitle,
    this.requestDiff,
    this.recent = const [],
    this.files = const [],
  });

  final BriefKind kind;

  /// What the user asked in this turn, on one line.
  final String? task;

  /// The plan's step being done: « 3/5 · Écrire les tests ».
  final String? step;

  /// The agent's last words (not its reasoning), shortened.
  final String? said;

  /// The command to allow, the question, the error, the limit, the summary.
  final String request;

  /// The tool's own title, when it says more than the command (« Write
  /// lib/main.dart »).
  final String? requestTitle;

  /// For a file change waiting for a yes: how big.
  final DiffStat? requestDiff;

  /// What the agent did just before, oldest first.
  final List<ActivityLine> recent;

  /// Once finished: the files it changed in this turn.
  final List<FileChange> files;

  /// The same, asking for [request] (a permission that came another way:
  /// Claude's hooks).
  TaskBrief withRequest(String request, {String? title}) => TaskBrief(
    kind: BriefKind.approval,
    task: task,
    step: step,
    said: said,
    request: request,
    requestTitle: title,
    recent: recent,
  );
}

/// The brief of a session in state [status].
TaskBrief briefOf(SessionLog log, AgentStatus status) {
  final kind = briefKindOf(status);
  final turns = log.turns;
  final items = log.items;
  final turn = turns.isEmpty ? null : turns.last;
  String? task;
  String? said;
  if (turn != null) {
    // The user's message that started the turn (the one just before, when
    // the turn records it after).
    for (var i = turn.start; i < (turn.end ?? items.length); i++) {
      final item = items[i];
      if (item is UserItem) {
        task = item.text;
        break;
      }
    }
    if (task == null) {
      for (var i = turn.start - 1; i >= 0; i--) {
        final item = items[i];
        if (item is UserItem) {
          task = item.text;
          break;
        }
      }
    }
    for (var i = (turn.end ?? items.length) - 1; i >= turn.start; i--) {
      final item = items[i];
      if (item is AgentItem && !item.thought && item.text.trim().isNotEmpty) {
        said = item.text;
        break;
      }
    }
  }
  final plan = log.plan;
  String? step;
  if (plan.isNotEmpty) {
    final i = plan.indexWhere((p) => p.status == PlanStatus.inProgress);
    final at = i >= 0 ? i : plan.indexWhere((p) => p.status == PlanStatus.pending);
    if (at >= 0) step = '${at + 1}/${plan.length} · ${_one(plan[at].content, 80)}';
  }

  String request = log.detail;
  String? requestTitle;
  DiffStat? requestDiff;
  final asked = log.pending.isEmpty ? null : log.pending.first;
  if (kind == BriefKind.approval && asked != null) {
    final tool = items.whereType<ToolItem>().where((t) => t.id == asked.toolCallId).firstOrNull;
    final title = tool?.title ?? asked.title;
    final diff = tool?.diff;
    if (diff != null) {
      requestDiff = diffStat(diff);
      request = '${_verbOfDiff(diff)} ${_fileName(diff.path) ?? diff.path}';
      requestTitle = diff.path;
    } else if (title.isNotEmpty && title != request) {
      requestTitle = _one(title, 120);
    }
  }

  final files = <FileChange>[];
  if (kind == BriefKind.finished && turn != null) {
    final byPath = <String, DiffStat>{};
    for (var i = turn.start; i < (turn.end ?? items.length); i++) {
      final item = items[i];
      if (item is ToolItem && item.diff != null && item.status != ToolStatus.failed) {
        final d = diffStat(item.diff!);
        final old = byPath[item.diff!.path];
        byPath[item.diff!.path] = old == null ? d : DiffStat(old.added + d.added, old.removed + d.removed);
      }
    }
    for (final e in byPath.entries) {
      files.add((name: _fileName(e.key) ?? e.key, diff: e.value));
    }
  }

  return TaskBrief(
    kind: kind,
    task: task == null ? null : _one(task, 140),
    step: step,
    // A finished turn's last words are its summary: the request line.
    said: said == null || kind == BriefKind.finished ? null : _one(_lastSentences(said), 200),
    request: kind == BriefKind.finished && said != null ? _one(_firstParagraph(said), 240) : request,
    requestTitle: requestTitle,
    requestDiff: requestDiff,
    recent: kind == BriefKind.finished ? const [] : activityOf(log, max: 3),
    files: files,
  );
}

/// The brief of an agent with no session (the demo): its line only.
TaskBrief briefOfAgent(Agent a) => TaskBrief(kind: briefKindOf(a.status), request: a.detail);

String _verbOfDiff(FileDiff d) => d.oldText == null ? 'Créer' : 'Modifier';

String _one(String s, [int max = 120]) {
  final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length <= max ? one : '${one.substring(0, max - 1)}…';
}

/// The end of a long message: what the agent says last is what leads to
/// its request.
String _lastSentences(String text) {
  final t = text.trim();
  final paragraphs = t.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();
  return paragraphs.isEmpty ? t : _stripMarkdown(paragraphs.last);
}

/// A summary's first useful paragraph, without Markdown marks.
String _firstParagraph(String text) {
  for (final p in text.trim().split(RegExp(r'\n\s*\n'))) {
    final clean = _stripMarkdown(p).trim();
    if (clean.isNotEmpty && !clean.startsWith('```')) return clean;
  }
  return _stripMarkdown(text);
}

String _stripMarkdown(String s) => s
    .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '');
