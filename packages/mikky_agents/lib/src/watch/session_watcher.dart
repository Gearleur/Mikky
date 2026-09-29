import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

import '../setup.dart';
import '../target.dart';

/// A session found in Claude's or Codex's files, kept up to date.
class WatchedSession {
  WatchedSession(this.path, this.provider, this.host);

  /// The file, as Windows reads it.
  final String path;
  final AgentProvider provider;
  final AgentHost host;
  final SessionLog log = SessionLog();

  /// Last write seen on the file.
  DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);

  /// Id of the first user message (Claude). A resumed session (« fork »)
  /// copies the history with the same ids: sessions sharing it are one
  /// conversation.
  String? firstMessage;

  int _offset = 0;
  final List<int> _partial = [];
  Object _reader = Object();

  String? get sessionId => log.sessionId;
}

/// Watches Claude's and Codex's session folders on one target and reads
/// the files as they grow (MVP spec §4.1): event-driven, no polling.
///
/// Windows: `Directory.watch`. WSL: Windows gets no events from WSL
/// folders, so a probe runs inside WSL with Mikky's Node ([wslWatchScript])
/// and prints one line per change; the files are then read through
/// `\\wsl.localhost`.
class SessionWatcher {
  SessionWatcher({
    required this.target,
    required this.claudeProjects,
    required this.codexSessions,
    this.node,
    this.watchScript,
    this.since = const Duration(days: 3),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// From an [AgentSetup]: its folders, its Node and probe.
  factory SessionWatcher.forSetup(AgentSetup setup, {Duration since = const Duration(days: 3)}) => SessionWatcher(
        target: setup.target,
        claudeProjects: setup.claudeProjects,
        codexSessions: setup.codexSessions,
        node: setup.node,
        watchScript: setup.watchScript,
        since: since,
      );

  final Target target;

  /// Session folders, in the target's own form.
  final String claudeProjects;
  final String codexSessions;

  /// WSL only: Mikky's Node and the probe script.
  final String? node;
  final String? watchScript;

  /// Files older than this are not read at start.
  final Duration since;
  final DateTime Function() _now;

  final Map<String, WatchedSession> _sessions = {};
  final _updates = StreamController<WatchedSession>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  Process? _probe;

  /// Every session read so far, by file.
  Map<String, WatchedSession> get sessions => Map.unmodifiable(_sessions);

  /// A session that changed.
  Stream<WatchedSession> get updates => _updates.stream;

  /// Reads the recent files, then follows the changes.
  Future<void> start() async {
    await _scan(claudeProjects);
    await _scan(codexSessions);
    if (target.host == AgentHost.wsl) {
      await _startProbe();
    } else {
      for (final root in [claudeProjects, codexSessions]) {
        final dir = Directory(root);
        if (!await dir.exists()) continue;
        _subs.add(dir.watch(recursive: true).listen((e) => changed(e.path)));
      }
    }
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final probe = _probe;
    _probe = null;
    if (probe != null) await target.kill(probe);
  }

  Future<void> _scan(String root) async {
    final dir = Directory(target.windowsPath(root));
    if (!await dir.exists()) return;
    final oldest = _now().subtract(since);
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File || _kind(e.path) == null) continue;
      if ((await e.lastModified()).isBefore(oldest)) continue;
      await changed(e.path);
    }
  }

  Future<void> _startProbe() async {
    final node = this.node, script = watchScript;
    if (node == null || script == null) return;
    final probe = await target.start(node, [script, claudeProjects, codexSessions]);
    _probe = probe;
    probe.stderr.drain<void>();
    _subs.add(probe.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
      try {
        final m = (jsonDecode(line) as Map).cast<String, dynamic>();
        final dir = m['dir'] as String?, file = m['file'] as String?;
        if (dir != null && file != null) changed(target.windowsPath('$dir/$file'));
      } on FormatException {
        // Not a probe line.
      }
    }));
  }

  AgentProvider? _kind(String path) {
    final p = path.replaceAll('\\', '/');
    if (!p.endsWith('.jsonl')) return null;
    final claude = target.windowsPath(claudeProjects).replaceAll('\\', '/');
    final codex = target.windowsPath(codexSessions).replaceAll('\\', '/');
    // Claude: projects/<folder>/<id>.jsonl (not the subagents' files).
    if (p.startsWith('$claude/') && p.substring(claude.length + 1).split('/').length == 2) return AgentProvider.claude;
    if (p.startsWith('$codex/') && p.split('/').last.startsWith('rollout-')) return AgentProvider.codex;
    return null;
  }

  /// Reads what was added to [path] (a Windows path) since last time.
  /// Calls for one file run one after the other. Public for tests; the
  /// watchers call it.
  Future<void> changed(String path) {
    final next = (_queues[path] ?? Future<void>.value()).then((_) => _readNew(path));
    _queues[path] = next;
    return next;
  }

  final Map<String, Future<void>> _queues = {};

  Future<void> _readNew(String path) async {
    final provider = _kind(path);
    if (provider == null) return;
    final file = File(path);
    final int length;
    try {
      length = await file.length();
    } on FileSystemException {
      return;
    }
    var s = _sessions[path] ??= WatchedSession(path, provider, target.host);
    if (length < s._offset) {
      // Rewritten from the start: read it again.
      s = _sessions[path] = WatchedSession(path, provider, target.host);
    }
    if (length == s._offset) return;
    final raf = await file.open();
    final List<int> bytes;
    try {
      await raf.setPosition(s._offset);
      bytes = await raf.read(length - s._offset);
    } finally {
      await raf.close();
    }
    s._offset += bytes.length;
    s.modified = await file.lastModified();
    s._partial.addAll(bytes);
    final end = s._partial.lastIndexOf(10);
    if (end < 0) return;
    final text = utf8.decode(s._partial.sublist(0, end), allowMalformed: true);
    s._partial.removeRange(0, end + 1);
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      final Map<String, dynamic> json;
      try {
        json = (jsonDecode(line) as Map).cast<String, dynamic>();
      } on FormatException {
        continue;
      }
      if (s.firstMessage == null && json['type'] == 'user' && json['uuid'] is String) s.firstMessage = json['uuid'] as String;
      s.log.applyAll(_read(s, json));
    }
    _updates.add(s);
  }

  List<SessionEvent> _read(WatchedSession s, Map<String, dynamic> line) {
    final reader = s._reader;
    if (reader is ClaudeTranscriptReader) return reader.read(line);
    if (reader is CodexRolloutReader) return reader.read(line);
    if (s.provider == AgentProvider.claude) {
      s._reader = ClaudeTranscriptReader();
    } else {
      s._reader = CodexRolloutReader();
    }
    return _read(s, line);
  }
}
