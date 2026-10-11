import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart' show WslPath;
import 'package:mikky_engine/mikky_engine.dart';

import 'job.dart';

/// Where commands run: Windows itself, or a WSL distribution (MVP spec
/// §3.4). Paths given to a target are in its own form (`C:\…` or `/home/…`).
abstract class Target {
  AgentHost get host;

  /// Starts [executable] with [args] in [cwd], with [env] added.
  Future<Process> start(String executable, List<String> args, {String? cwd, Map<String, String> env = const {}});

  /// Runs to the end and returns what it printed. Output is decoded
  /// leniently (`wsl.exe` prints its own errors in UTF-16). [input] goes to
  /// stdin: the way to pass a multi-line script (newlines do not survive
  /// the Windows command line).
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
    String? input,
  }) async {
    final p = await start(executable, args, cwd: cwd, env: env);
    final out = p.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
    final err = p.stderr.transform(const Utf8Decoder(allowMalformed: true)).join();
    if (input != null) p.stdin.add(utf8.encode(input));
    await p.stdin.close();
    final code = await p.exitCode;
    return ProcessResult(p.pid, code, await out, await err);
  }

  /// Stops [process] and everything it started.
  Future<void> kill(Process process);

  /// Puts [process] in its own Windows job (see [ProcessJob]), so [kill]
  /// ends its whole tree and Mikky's end ends it too. Right after start.
  void contain(Process process) {
    final job = ProcessJob.forProcess(process.pid);
    if (job == null) return;
    _jobs[process.pid] = job;
    // Once it ends by itself, the job goes too, and with it whatever the
    // agent left running in the background.
    process.exitCode.then((_) => _jobs.remove(process.pid)?.close());
  }

  final Map<int, ProcessJob> _jobs = {};

  /// Ends [process]'s job if it has one. True if it did.
  bool _endJob(Process process) {
    final job = _jobs.remove(process.pid);
    if (job == null) return false;
    job.terminate();
    return true;
  }

  /// Where a file of this target is seen from Windows (to read it).
  String windowsPath(String path);
}

class WindowsTarget extends Target {
  @override
  AgentHost get host => AgentHost.windows;

  @override
  Future<Process> start(String executable, List<String> args, {String? cwd, Map<String, String> env = const {}}) =>
      Process.start(executable, args, workingDirectory: cwd, environment: env, runInShell: executable.endsWith('.cmd'));

  @override
  Future<void> kill(Process process) async {
    if (_endJob(process)) return;
    // No job (Windows refused it): /T ends the tree as far as it is known.
    await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
  }

  @override
  String windowsPath(String path) => path;
}

class WslTarget extends Target {
  WslTarget({this.distro = 'Ubuntu'});

  final String distro;

  @override
  AgentHost get host => AgentHost.wsl;

  /// A login shell: without it, `claude` and `codex` may resolve to the
  /// Windows ones (WSL appends the Windows PATH).
  @override
  Future<Process> start(String executable, List<String> args, {String? cwd, Map<String, String> env = const {}}) {
    final exports = env.entries.map((e) => 'export ${e.key}=${shellQuote(e.value)}; ').join();
    final command = [executable, ...args].map(shellQuote).join(' ');
    return Process.start('wsl.exe', [
      '-d',
      distro,
      if (cwd != null) ...['--cd', cwd],
      '--',
      'bash',
      '-lc',
      '${exports}exec $command',
    ]);
  }

  /// Ending `wsl.exe` ends what it runs (checked in the A0 probe).
  @override
  Future<void> kill(Process process) async {
    if (_endJob(process)) return;
    process.kill();
  }

  @override
  String windowsPath(String path) => WslPath(distro: distro).windowsPath(path);

  /// A Windows path as WSL sees it: `C:\x` → `/mnt/c/x`,
  /// `\\wsl.localhost\Ubuntu\home\x` → `/home/x`.
  String linuxPath(String path) => WslPath(distro: distro).linuxPath(path);
}

/// Single-quotes [s] for bash.
String shellQuote(String s) => RegExp(r'^[A-Za-z0-9_./:=@%+-]+$').hasMatch(s) ? s : "'${s.replaceAll("'", r"'\''")}'";
