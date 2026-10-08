import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

import 'paths.dart';

/// Where a session started outside Mikky runs, as its hooks told `mikkyd`
/// (`hooks.origin`, `daemon/mikkyd/src/hooks.rs`): the window found among
/// the hook's parent processes (a terminal, VS Code) and the terminal's own
/// words.
class SessionOrigin {
  const SessionOrigin({this.windowPid, this.windowHandle, this.windowExe, this.termProgram, this.vscodePid, this.wtSession, this.cwd});

  /// What `mikkyd` answers; a field of an unexpected type is left out.
  factory SessionOrigin.fromJson(Map<String, Object?> j) {
    String? text(String key) => j[key] is String && (j[key]! as String).isNotEmpty ? j[key]! as String : null;
    int? number(String key) => j[key] is num ? (j[key]! as num).toInt() : null;
    return SessionOrigin(
      windowPid: number('windowPid'),
      windowHandle: number('windowHandle'),
      windowExe: text('windowExe'),
      termProgram: text('termProgram'),
      vscodePid: text('vscodePid'),
      wtSession: text('wtSession'),
      cwd: text('cwd'),
    );
  }

  /// The process owning the session's window, and that window.
  final int? windowPid;
  final int? windowHandle;

  /// Its executable (`WindowsTerminal.exe`, `Code.exe`…).
  final String? windowExe;

  /// `TERM_PROGRAM` (`vscode`…), `VSCODE_PID`, `WT_SESSION` (Windows Terminal).
  final String? termProgram;
  final String? vscodePid;
  final String? wtSession;
  final String? cwd;
}

/// One way to show the user where a session runs, tried in order by
/// `AgentsService.reveal`.
sealed class RevealStep {
  const RevealStep();
}

/// Brings this window forward (restored if minimized). Done by the app,
/// which just got the click: Windows lets only it take the foreground.
class BringWindow extends RevealStep {
  const BringWindow(this.pid, this.handle);

  final int pid;

  /// The window as the hook saw it; 0: any window of [pid].
  final int handle;

  @override
  bool operator ==(Object other) => other is BringWindow && other.pid == pid && other.handle == handle;

  @override
  int get hashCode => Object.hash(pid, handle);

  @override
  String toString() => 'BringWindow($pid, $handle)';
}

/// Opens VS Code with these arguments (a folder, or `--remote wsl+…` and
/// a Linux folder).
class OpenInVsCode extends RevealStep {
  const OpenInVsCode(this.args);

  final List<String> args;

  @override
  bool operator ==(Object other) => other is OpenInVsCode && other.args.join('\u0000') == args.join('\u0000');

  @override
  int get hashCode => Object.hashAll(args);

  @override
  String toString() => 'OpenInVsCode($args)';
}

/// How to reveal a session (Ctrl + click on an agent, 2026-10-08): its
/// window first, for a session started outside Mikky whose hooks found one;
/// then VS Code on its folder — through WSL for a WSL session. An agent
/// Mikky runs has no window of its own: VS Code on its folder. Nothing when
/// there is neither window nor folder.
List<RevealStep> revealSteps({
  required AgentOrigin origin,
  AgentHost host = AgentHost.windows,
  String? cwd,
  SessionOrigin? seen,
  String distro = 'Ubuntu',
}) {
  final steps = <RevealStep>[];
  final pid = seen?.windowPid;
  if (origin == AgentOrigin.external && pid != null && pid > 0) steps.add(BringWindow(pid, seen?.windowHandle ?? 0));
  final folder = (cwd != null && cwd.isNotEmpty) ? cwd : seen?.cwd;
  if (folder != null && folder.isNotEmpty) {
    if (host == AgentHost.wsl || hostOfFolder(folder) == AgentHost.wsl) {
      final named = RegExp(r'^\\\\wsl(?:\.localhost|\$)\\([^\\]+)', caseSensitive: false).firstMatch(folder)?[1];
      final d = named ?? distro;
      steps.add(OpenInVsCode(['--remote', 'wsl+$d', WslPath(distro: d).linuxPath(folder)]));
    } else {
      steps.add(OpenInVsCode([folder]));
    }
  }
  return steps;
}

/// VS Code's command line (`code.cmd` on Windows): on the PATH, else where
/// its installers put it. Null when VS Code is not found.
String? findVsCode({Map<String, String>? environment, bool Function(String path)? exists, bool? windows}) {
  final env = environment ?? Platform.environment;
  final there = exists ?? (p) => File(p).existsSync();
  windows ??= Platform.isWindows;
  final names = windows ? const ['code.cmd', 'code.exe'] : const ['code'];
  final pathVar = env['PATH'] ?? env['Path'] ?? '';
  final sep = windows ? ';' : ':';
  final slash = windows ? r'\' : '/';
  for (final dir in pathVar.split(sep)) {
    if (dir.trim().isEmpty) continue;
    for (final n in names) {
      final p = dir.endsWith(slash) ? '$dir$n' : '$dir$slash$n';
      if (there(p)) return p;
    }
  }
  if (!windows) return null;
  final local = env['LOCALAPPDATA'];
  for (final base in [if (local != null) '$local\\Programs', env['ProgramFiles'], env['ProgramW6432']]) {
    if (base == null || base.isEmpty) continue;
    final p = '$base\\Microsoft VS Code\\bin\\code.cmd';
    if (there(p)) return p;
  }
  return null;
}
