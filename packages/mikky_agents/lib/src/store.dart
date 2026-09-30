import 'dart:convert';
import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

/// An agent Mikky launched, as kept on disk to find it again after a
/// restart. Never a conversation (it stays in Claude's / Codex's files),
/// never a credential.
class StoredAgent {
  const StoredAgent({
    required this.id,
    required this.provider,
    required this.host,
    required this.cwd,
    required this.permissions,
    required this.createdAt,
    this.sessionId,
    this.title,
    this.model,
  });

  factory StoredAgent.fromJson(Map<String, dynamic> j) => StoredAgent(
        id: j['id'] as String,
        provider: AgentProvider.values.byName(j['provider'] as String),
        host: AgentHost.values.byName(j['host'] as String),
        cwd: j['cwd'] as String,
        permissions: PermissionMode.values.byName(j['permissions'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        sessionId: j['sessionId'] as String?,
        title: j['title'] as String?,
        model: j['model'] as String?,
      );

  final String id;
  final AgentProvider provider;
  final AgentHost host;
  final String cwd;
  final PermissionMode permissions;
  final DateTime createdAt;
  final String? sessionId;
  final String? title;
  final String? model;

  StoredAgent copyWith({String? sessionId, String? title}) => StoredAgent(
        id: id,
        provider: provider,
        host: host,
        cwd: cwd,
        permissions: permissions,
        createdAt: createdAt,
        sessionId: sessionId ?? this.sessionId,
        title: title ?? this.title,
        model: model,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider.name,
        'host': host.name,
        'cwd': cwd,
        'permissions': permissions.name,
        'createdAt': createdAt.toIso8601String(),
        if (sessionId != null) 'sessionId': sessionId,
        if (title != null) 'title': title,
        if (model != null) 'model': model,
      };
}

/// The last choices made for a folder in the new-agent screen.
class LaunchChoice {
  const LaunchChoice({required this.provider, required this.host, required this.permissions, this.model});

  factory LaunchChoice.fromJson(Map<String, dynamic> j) => LaunchChoice(
        provider: AgentProvider.values.byName(j['provider'] as String),
        host: AgentHost.values.byName(j['host'] as String),
        permissions: PermissionMode.values.byName(j['permissions'] as String),
        model: j['model'] as String?,
      );

  final AgentProvider provider;
  final AgentHost host;
  final PermissionMode permissions;
  final String? model;

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'host': host.name,
        'permissions': permissions.name,
        if (model != null) 'model': model,
      };
}

/// What the user did with a session (any session: Mikky's or one started
/// elsewhere): its own name, pinned, archived, an error marked as settled,
/// or forgotten.
class SessionMark {
  const SessionMark({this.name, this.pinned = false, this.archived = false, this.settledAt, this.pausedAt, this.forgotten = false});

  factory SessionMark.fromJson(Map<String, dynamic> j) => SessionMark(
        name: j['name'] as String?,
        pinned: j['pinned'] == true,
        archived: j['archived'] == true,
        settledAt: j['settledAt'] == null ? null : DateTime.parse(j['settledAt'] as String),
        pausedAt: j['pausedAt'] == null ? null : DateTime.parse(j['pausedAt'] as String),
        forgotten: j['forgotten'] == true,
      );

  /// The user's name for it, in place of the agent's title.
  final String? name;
  final bool pinned;

  /// Off the home, in « Archives ».
  final bool archived;

  /// The error was seen and settled then: until something new happens,
  /// the session counts as done.
  final DateTime? settledAt;

  /// Put on hold then by the user (« Pause »), until « Reprendre » or a
  /// new message.
  final DateTime? pausedAt;

  /// Deleted from Mikky: never shown again.
  final bool forgotten;

  bool get isEmpty => name == null && !pinned && !archived && settledAt == null && pausedAt == null && !forgotten;

  SessionMark copyWith({
    String? name,
    bool clearName = false,
    bool? pinned,
    bool? archived,
    DateTime? settledAt,
    DateTime? pausedAt,
    bool clearPaused = false,
    bool? forgotten,
  }) =>
      SessionMark(
        name: clearName ? null : (name ?? this.name),
        pinned: pinned ?? this.pinned,
        archived: archived ?? this.archived,
        settledAt: settledAt ?? this.settledAt,
        pausedAt: clearPaused ? null : (pausedAt ?? this.pausedAt),
        forgotten: forgotten ?? this.forgotten,
      );

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (pinned) 'pinned': true,
        if (archived) 'archived': true,
        if (settledAt != null) 'settledAt': settledAt!.toIso8601String(),
        if (pausedAt != null) 'pausedAt': pausedAt!.toIso8601String(),
        if (forgotten) 'forgotten': true,
      };
}

/// `%APPDATA%\Mikky\agents.json`: Mikky's agents, recent folders, last
/// choices per folder (MVP spec §7), and the marks on sessions. A broken
/// file is set aside, not lost.
class AgentStore {
  AgentStore(this.file);

  /// The default place, next to `settings.json`.
  factory AgentStore.standard() => AgentStore(File('${Platform.environment['APPDATA']}\\Mikky\\agents.json'));

  final File file;
  final List<StoredAgent> agents = [];
  final List<String> recentFolders = [];
  final Map<String, LaunchChoice> choices = {};

  /// Marks by session key (`claude:<id>`, `codex:<id>`, or an agent id
  /// while it has no session yet).
  final Map<String, SessionMark> marks = {};

  static const maxRecentFolders = 8;

  Future<void> load() async {
    agents.clear();
    recentFolders.clear();
    choices.clear();
    marks.clear();
    if (!await file.exists()) return;
    try {
      final j = (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
      for (final a in (j['agents'] as List?) ?? const []) {
        agents.add(StoredAgent.fromJson((a as Map).cast<String, dynamic>()));
      }
      recentFolders.addAll(((j['recentFolders'] as List?) ?? const []).cast<String>());
      for (final e in ((j['choices'] as Map?) ?? const {}).entries) {
        choices[e.key as String] = LaunchChoice.fromJson((e.value as Map).cast<String, dynamic>());
      }
      for (final e in ((j['marks'] as Map?) ?? const {}).entries) {
        marks[e.key as String] = SessionMark.fromJson((e.value as Map).cast<String, dynamic>());
      }
    } catch (_) {
      await file.rename('${file.path}.broken');
      agents.clear();
      recentFolders.clear();
      choices.clear();
      marks.clear();
    }
  }

  /// Writes the file. Saves run one after the other; [saved] completes
  /// when the last one is written.
  Future<void> save() => _saving = _saving.then((_) => _write()).catchError((Object _) {});

  Future<void> _saving = Future<void>.value();
  Future<void> get saved => _saving;

  Future<void> _write() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'agents': [for (final a in agents) a.toJson()],
      'recentFolders': recentFolders,
      'choices': {for (final e in choices.entries) e.key: e.value.toJson()},
      'marks': {for (final e in marks.entries) e.key: e.value.toJson()},
    }));
    await tmp.rename(file.path);
  }

  /// Adds or replaces [agent] (by id).
  void put(StoredAgent agent) {
    final i = agents.indexWhere((a) => a.id == agent.id);
    if (i < 0) {
      agents.add(agent);
    } else {
      agents[i] = agent;
    }
  }

  StoredAgent? bySession(String sessionId) {
    for (final a in agents) {
      if (a.sessionId == sessionId) return a;
    }
    return null;
  }

  SessionMark mark(String key) => marks[key] ?? const SessionMark();

  /// Changes the mark of [key] (an empty mark is dropped).
  void setMark(String key, SessionMark mark) {
    if (mark.isEmpty) {
      marks.remove(key);
    } else {
      marks[key] = mark;
    }
  }

  /// Remembers [folder] first in the recent list, with its [choice].
  void usedFolder(String folder, LaunchChoice choice) {
    recentFolders
      ..remove(folder)
      ..insert(0, folder);
    if (recentFolders.length > maxRecentFolders) recentFolders.removeRange(maxRecentFolders, recentFolders.length);
    choices[folder] = choice;
  }
}
