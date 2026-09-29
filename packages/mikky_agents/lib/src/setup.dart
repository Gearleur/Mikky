import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

import 'acp/agent_run.dart';
import 'target.dart';

/// Versions checked in the A0 probe (2026-09-29).
const claudeAcpPackage = '@agentclientprotocol/claude-agent-acp@0.84.0';
const codexAcpPackage = '@agentclientprotocol/codex-acp@2.0.0';
const privateNodeVersion = 'v24.19.0';

/// The oldest Node the adapters accept (`claude-agent-acp`: ≥ 22).
const minNodeMajor = 22;

/// What is missing on a target before Mikky can launch agents there.
class SetupStatus {
  const SetupStatus({required this.node, required this.adapters, this.nodeVersion});

  /// A Node recent enough for the adapters.
  final bool node;
  final String? nodeVersion;

  /// Both adapters are installed in Mikky's folder (and, in WSL, the
  /// watch probe).
  final bool adapters;

  bool get ready => node && adapters;
}

/// Mikky's own folder on a target: the adapters (and, in WSL, its private
/// Node) live there, never in the user's global install (MVP spec §3.1).
///
/// Windows: `%LOCALAPPDATA%\Mikky`, system Node. WSL: `~/.local/share/mikky`,
/// private Node (the user's choice of 2026-09-29: Ubuntu's Node 18 stays).
class AgentSetup {
  AgentSetup._(this.target, this.home, this.dir);

  static Future<AgentSetup> windows({String? dir}) async => AgentSetup._(
        WindowsTarget(),
        Platform.environment['USERPROFILE'] ?? '',
        dir ?? '${Platform.environment['LOCALAPPDATA']}\\Mikky',
      );

  static Future<AgentSetup> wsl({String distro = 'Ubuntu'}) async {
    final target = WslTarget(distro: distro);
    final home = ((await target.run('printenv', ['HOME'])).stdout as String).trim();
    return AgentSetup._(target, home, '$home/.local/share/mikky');
  }

  final Target target;

  /// The user's home on the target (`C:\Users\…` or `/home/…`).
  final String home;

  /// Mikky's folder on the target.
  final String dir;

  bool get _wsl => target.host == AgentHost.wsl;
  String get _sep => _wsl ? '/' : r'\';
  String get node => _wsl ? '$dir/node/bin/node' : 'node';
  String get acpDir => '$dir${_sep}acp';

  String adapterScript(AgentProvider provider) {
    final pkg = provider == AgentProvider.claude ? 'claude-agent-acp' : 'codex-acp';
    return [acpDir, 'node_modules', '@agentclientprotocol', pkg, 'dist', 'index.js'].join(_sep);
  }

  /// Where Claude and Codex keep their sessions on this target.
  String get claudeProjects => [home, '.claude', 'projects'].join(_sep);
  String get codexSessions => [home, '.codex', 'sessions'].join(_sep);

  /// The file-watching probe for WSL (see [SessionWatcher]).
  String get watchScript => '$dir/watch.mjs';

  Future<SetupStatus> check() async {
    String? version;
    try {
      final r = await target.run(node, ['--version']);
      if (r.exitCode == 0) version = (r.stdout as String).trim();
    } on ProcessException {
      version = null;
    }
    final major = int.tryParse(RegExp(r'^v(\d+)').firstMatch(version ?? '')?[1] ?? '') ?? 0;
    final adapters = await _exists(adapterScript(AgentProvider.claude)) &&
        await _exists(adapterScript(AgentProvider.codex)) &&
        (!_wsl || await _exists(watchScript));
    return SetupStatus(node: major >= minNodeMajor, nodeVersion: version, adapters: adapters);
  }

  Future<bool> _exists(String path) async {
    if (!_wsl) return File(path).exists();
    return (await target.run('test', ['-f', path])).exitCode == 0;
  }

  /// Installs what [check] found missing: in WSL the private Node (checked
  /// against nodejs.org's SHA-256), then the two adapters with npm, and the
  /// watch probe. Throws with npm's output if it fails.
  Future<void> install() async {
    final ProcessResult r;
    if (_wsl) {
      r = await target.run('bash', ['-s'], input: _wslInstallScript(dir));
    } else {
      await Directory(acpDir).create(recursive: true);
      r = await target.run('npm.cmd', ['install', '--prefix', acpDir, '--no-fund', '--no-audit', claudeAcpPackage, codexAcpPackage]);
    }
    if (r.exitCode != 0) throw ProcessException(_wsl ? 'bash' : 'npm', const [], '${r.stdout}\n${r.stderr}'.trim(), r.exitCode);
  }

  /// Path of the user's own `claude` on the target, if installed: the
  /// adapter runs it (`CLAUDE_CODE_EXECUTABLE`), not a copy of its own.
  Future<String?> claudeExecutable() async {
    if (!_wsl) {
      final native = File('$home\\.local\\bin\\claude.exe');
      if (await native.exists()) return native.path;
      final r = await Process.run('where', ['claude']);
      return r.exitCode == 0 ? (r.stdout as String).split('\n').first.trim() : null;
    }
    final r = await target.run('bash', ['-lc', 'command -v claude']);
    final path = (r.stdout as String).trim();
    return r.exitCode == 0 && path.startsWith('/') ? path : null;
  }

  /// Starts the adapter of [provider] in [cwd] (a path of this target, or
  /// a Windows path that WSL can reach).
  Future<AgentRun> spawn(AgentProvider provider, {required String cwd}) async {
    final env = <String, String>{};
    if (provider == AgentProvider.claude) {
      final claude = await claudeExecutable();
      if (claude != null) env['CLAUDE_CODE_EXECUTABLE'] = claude;
    }
    final t = target;
    final where = t is WslTarget ? t.linuxPath(cwd) : cwd;
    return AgentRun.spawn(target, node, [adapterScript(provider)], cwd: where, env: env);
  }
}

String _wslInstallScript(String dir) => '''
set -e
D=$dir
V=$privateNodeVersion
mkdir -p "\$D"
cd "\$D"
if [ ! -x node/bin/node ]; then
  curl -fsSL "https://nodejs.org/dist/\$V/node-\$V-linux-x64.tar.xz" -o node.tar.xz
  curl -fsSL "https://nodejs.org/dist/\$V/SHASUMS256.txt" | grep " node-\$V-linux-x64.tar.xz\$" | sed "s/node-\$V-linux-x64.tar.xz/node.tar.xz/" | sha256sum -c -
  mkdir -p node && tar -xJf node.tar.xz -C node --strip-components=1 && rm node.tar.xz
fi
mkdir -p acp
[ -f acp/package.json ] || echo '{"name":"mikky-acp","private":true}' > acp/package.json
PATH="\$D/node/bin:\$PATH" npm install --prefix acp --no-fund --no-audit $claudeAcpPackage $codexAcpPackage
cat > watch.mjs <<'MIKKY'
$wslWatchScript
MIKKY
''';

/// Runs in WSL with Mikky's Node: one JSON line per change in the watched
/// folders (inotify, no polling). Windows gets no file events from WSL
/// folders (A0 probe), hence this probe. Ends with `wsl.exe`.
const wslWatchScript = '''
import fs from 'node:fs';
for (const dir of process.argv.slice(2)) {
  if (!fs.existsSync(dir)) { console.log(JSON.stringify({ missing: dir })); continue; }
  fs.watch(dir, { recursive: true }, (type, file) => { if (file) console.log(JSON.stringify({ dir, file })); });
}
console.log(JSON.stringify({ ready: true }));
''';
