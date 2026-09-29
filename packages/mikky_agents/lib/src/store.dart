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

/// `%APPDATA%\Mikky\agents.json`: Mikky's agents, recent folders and last
/// choices per folder (MVP spec §7). A broken file is set aside, not lost.
class AgentStore {
  AgentStore(this.file);

  /// The default place, next to `settings.json`.
  factory AgentStore.standard() => AgentStore(File('${Platform.environment['APPDATA']}\\Mikky\\agents.json'));

  final File file;
  final List<StoredAgent> agents = [];
  final List<String> recentFolders = [];
  final Map<String, LaunchChoice> choices = {};

  static const maxRecentFolders = 8;

  Future<void> load() async {
    agents.clear();
    recentFolders.clear();
    choices.clear();
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
    } catch (_) {
      await file.rename('${file.path}.broken');
      agents.clear();
      recentFolders.clear();
      choices.clear();
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

  /// Remembers [folder] first in the recent list, with its [choice].
  void usedFolder(String folder, LaunchChoice choice) {
    recentFolders
      ..remove(folder)
      ..insert(0, folder);
    if (recentFolders.length > maxRecentFolders) recentFolders.removeRange(maxRecentFolders, recentFolders.length);
    choices[folder] = choice;
  }
}
