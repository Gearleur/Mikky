import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

import 'target.dart';

/// Is the agent tool there, and is its user signed in (MVP spec §3.3)?
/// Mikky only asks the tools; it never reads or writes a credential.
class AuthStatus {
  const AuthStatus({required this.installed, required this.loggedIn, this.plan});

  final bool installed;
  final bool loggedIn;

  /// Claude: `pro`, `max`…; Codex: `ChatGPT`.
  final String? plan;

  @override
  String toString() => 'AuthStatus(installed: $installed, loggedIn: $loggedIn, plan: $plan)';
}

/// Asks `claude auth status` or `codex login status` on [target].
/// [claude]: the path of the user's `claude` when known.
Future<AuthStatus> authStatus(Target target, AgentProvider provider, {String? claude}) async {
  try {
    if (provider == AgentProvider.claude) {
      final exe = claude ?? 'claude';
      final r = target.host == AgentHost.wsl ? await target.run('bash', ['-lc', '$exe auth status']) : await target.run(exe, ['auth', 'status']);
      return parseClaudeStatus(r.exitCode, r.stdout as String);
    }
    final r = target.host == AgentHost.wsl ? await target.run('bash', ['-lc', 'codex login status']) : await target.run('codex.cmd', ['login', 'status']);
    return parseCodexStatus(r.exitCode, '${r.stdout}\n${r.stderr}');
  } on ProcessException {
    return const AuthStatus(installed: false, loggedIn: false);
  }
}

AuthStatus parseClaudeStatus(int exitCode, String stdout) {
  final start = stdout.indexOf('{');
  if (start < 0) return AuthStatus(installed: exitCode != 127 && stdout.trim().isNotEmpty, loggedIn: false);
  try {
    final json = (jsonDecode(stdout.substring(start)) as Map).cast<String, dynamic>();
    return AuthStatus(installed: true, loggedIn: json['loggedIn'] == true, plan: json['subscriptionType'] as String?);
  } on FormatException {
    return const AuthStatus(installed: true, loggedIn: false);
  }
}

AuthStatus parseCodexStatus(int exitCode, String output) {
  if (exitCode == 127 || output.contains('command not found')) return const AuthStatus(installed: false, loggedIn: false);
  final m = RegExp(r'Logged in using (\S+)').firstMatch(output);
  if (m != null) return AuthStatus(installed: true, loggedIn: true, plan: m[1]);
  return const AuthStatus(installed: true, loggedIn: false);
}

/// Where a sign-in stands.
sealed class LoginState {
  const LoginState();
}

/// Open [url] and, for Codex, type [code] (it expires in 15 minutes).
class LoginPrompt extends LoginState {
  const LoginPrompt(this.url, [this.code]);

  final String url;
  final String? code;
}

class LoginDone extends LoginState {
  const LoginDone({required this.ok, this.message});

  final bool ok;

  /// Why it failed (a network error while waiting, the code expired…).
  final String? message;
}

/// A sign-in in progress: `codex login --device-auth` (a link and a code,
/// as Paperclip's `device-login-runner.ts`) or `claude auth login` (opens
/// the browser; the link is shown too). The tool keeps the credential.
/// Codex prints nothing without a terminal: in WSL it runs under `script`.
/// The raw output is never logged or kept.
class Login {
  Login._(this._process) {
    _process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(_onText);
    _process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(_onText);
    _process.exitCode.then((code) {
      if (_states.isClosed) return;
      _states.add(LoginDone(ok: code == 0, message: code == 0 ? null : _lastLine));
      _states.close();
    });
  }

  static Future<Login> start(Target target, AgentProvider provider) async {
    final command = provider == AgentProvider.codex ? 'codex login --device-auth' : 'claude auth login';
    final Process p;
    if (target.host == AgentHost.wsl) {
      p = await target.start('script', ['-q', '-f', '-c', command, '/dev/null']);
    } else {
      final parts = command.split(' ');
      p = await target.start(provider == AgentProvider.codex ? 'codex.cmd' : 'claude', parts.sublist(1));
    }
    return Login._(p);
  }

  final Process _process;
  final _states = StreamController<LoginState>.broadcast();
  final _buffer = StringBuffer();
  bool _prompted = false;
  String? _lastLine;

  Stream<LoginState> get states => _states.stream;

  void _onText(String chunk) {
    final text = stripAnsi(chunk);
    for (final line in text.split('\n')) {
      if (line.trim().isNotEmpty) _lastLine = line.trim();
    }
    if (_prompted) return;
    _buffer.write(text);
    final prompt = parseLoginPrompt(_buffer.toString());
    if (prompt == null) return;
    _prompted = true;
    _buffer.clear();
    _states.add(prompt);
  }

  /// Gives up: the tool stops waiting.
  void cancel() => _process.kill();
}

/// The link (and Codex's one-time code) in a login command's output.
LoginPrompt? parseLoginPrompt(String text) {
  final url = RegExp(r'https://\S+').firstMatch(text)?[0];
  if (url == null) return null;
  if (url.contains('/codex/device')) {
    final code = RegExp(r'\b[A-Z0-9]{4}-[A-Z0-9]{4,6}\b').firstMatch(text)?[0];
    return code == null ? null : LoginPrompt(url, code);
  }
  return LoginPrompt(url);
}

String stripAnsi(String s) => s.replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]|\x1B\][^\x07]*\x07|\r'), '');
