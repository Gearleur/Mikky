import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';
import 'package:mikky_agents/src/auth.dart';

import 'target.dart';

/// Asks `claude auth status` or `codex login status` on [target].
/// [claude]: the path of the user's `claude` when known.
Future<AuthStatus> authStatus(Target target, AgentProvider provider, {String? claude}) async {
  try {
    if (provider == AgentProvider.claude) {
      final exe = claude ?? 'claude';
      final r = target.host == AgentHost.wsl
          ? await target.run('bash', ['-lc', '$exe auth status'])
          : await target.run(exe, ['auth', 'status']);
      return parseClaudeStatus(r.exitCode, r.stdout as String);
    }
    final r = target.host == AgentHost.wsl
        ? await target.run('bash', ['-lc', 'codex login status'])
        : await target.run('codex.cmd', ['login', 'status']);
    return parseCodexStatus(r.exitCode, '${r.stdout}\n${r.stderr}');
  } on ProcessException {
    return const AuthStatus(installed: false, loggedIn: false);
  }
}
