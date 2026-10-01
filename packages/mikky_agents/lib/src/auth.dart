import 'dart:async';
import 'dart:convert';

import 'package:mikky_engine/mikky_engine.dart';

import 'daemon/daemon_client.dart';

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

AuthStatus parseClaudeStatus(int exitCode, String stdout) {
  final start = stdout.indexOf('{');
  if (start < 0) {
    return AuthStatus(installed: exitCode != 127 && stdout.trim().isNotEmpty, loggedIn: false);
  }
  try {
    final json = (jsonDecode(stdout.substring(start)) as Map).cast<String, dynamic>();
    return AuthStatus(installed: true, loggedIn: json['loggedIn'] == true, plan: json['subscriptionType'] as String?);
  } on FormatException {
    return const AuthStatus(installed: true, loggedIn: false);
  }
}

AuthStatus parseCodexStatus(int exitCode, String output) {
  if (exitCode == 127 || output.contains('command not found')) {
    return const AuthStatus(installed: false, loggedIn: false);
  }
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
  Login._remote(this._client, this._host, this._id) {
    _sub = _client!.notifications.listen((n) {
      if (n.params['login'] != _id || _states.isClosed) return;
      if (n.method == 'login.output') _onText(n.params['text'] as String);
      if (n.method == 'login.done') {
        _emit(LoginDone(ok: n.params['ok'] == true, message: n.params['ok'] == true ? null : _lastLine));
        _states.close();
        _sub?.cancel();
      }
    });
    _client.done.then((_) {
      if (_states.isClosed) return;
      _emit(const LoginDone(ok: false, message: 'Connexion au moteur interrompue.'));
      _states.close();
      _sub?.cancel();
    });
  }

  static Future<Login> remote(DaemonClient client, AgentHost host, AgentProvider provider) async {
    final id = 'login-${DateTime.now().microsecondsSinceEpoch}';
    final login = Login._remote(client, host, id);
    try {
      await client.request('tools.login', {'host': host.name, 'provider': provider.name, 'login': id});
    } catch (_) {
      login.cancel();
      rethrow;
    }
    return login;
  }

  final DaemonClient? _client;
  final AgentHost? _host;
  final String? _id;
  StreamSubscription<DaemonNotification>? _sub;
  LoginState? _latest;
  void _emit(LoginState state) {
    _latest = state;
    _states.add(state);
  }

  final _states = StreamController<LoginState>.broadcast();
  final _buffer = StringBuffer();
  bool _prompted = false;
  String? _lastLine;

  Stream<LoginState> get states => Stream.multi((sink) {
    final sub = _states.stream.listen(sink.addSync, onError: sink.addErrorSync, onDone: sink.closeSync);
    if (_latest case final state?) sink.addSync(state);
    sink.onCancel = sub.cancel;
  });

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
    _emit(prompt);
  }

  /// Gives up: the tool stops waiting.
  void cancel() {
    if (_client case final client?) {
      unawaited(client.request('tools.cancelLogin', {'host': _host!.name, 'login': _id}).catchError((Object _) => null));
      _sub?.cancel();
      if (!_states.isClosed) _states.close();
    }
  }
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
