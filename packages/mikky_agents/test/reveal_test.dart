import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  const terminal = SessionOrigin(
    windowPid: 4242,
    windowHandle: 6553,
    windowExe: 'WindowsTerminal.exe',
    wtSession: 'abc',
    cwd: r'C:\p',
  );

  test('a session in a terminal: its window first, then VS Code on its folder', () {
    expect(revealSteps(origin: AgentOrigin.external, cwd: r'C:\projet', seen: terminal), [
      const BringWindow(4242, 6553),
      const OpenInVsCode([r'C:\projet']),
    ]);
    // No folder known but the hooks': theirs.
    expect(revealSteps(origin: AgentOrigin.external, seen: terminal), [
      const BringWindow(4242, 6553),
      const OpenInVsCode([r'C:\p']),
    ]);
    // A window but no handle: any window of the process.
    expect(revealSteps(origin: AgentOrigin.external, seen: const SessionOrigin(windowPid: 7)), [
      const BringWindow(7, 0),
    ]);
  });

  test('a session in VS Code: the window titled with its folder, then VS Code on it', () {
    const vsCode = SessionOrigin(windowPid: 77, windowHandle: 88, windowExe: 'Code.exe');
    expect(revealSteps(origin: AgentOrigin.external, cwd: r'C:\Users\a\projet\mikky\', seen: vsCode), [
      const BringWindow(77, 88, title: 'mikky'),
      const OpenInVsCode([r'C:\Users\a\projet\mikky\']),
    ]);
    // A terminal's title says nothing of the folder.
    expect(
      revealSteps(origin: AgentOrigin.external, cwd: r'C:\projet', seen: terminal).first,
      const BringWindow(4242, 6553),
    );
  });

  test('no hooks seen: VS Code on the folder, or nothing', () {
    expect(revealSteps(origin: AgentOrigin.external, cwd: r'C:\projet'), [
      const OpenInVsCode([r'C:\projet']),
    ]);
    expect(revealSteps(origin: AgentOrigin.external), isEmpty);
    expect(revealSteps(origin: AgentOrigin.external, cwd: ''), isEmpty);
  });

  test('an agent Mikky runs: VS Code on its folder, never a window', () {
    expect(revealSteps(origin: AgentOrigin.mikky, cwd: r'C:\projet', seen: terminal), [
      const OpenInVsCode([r'C:\projet']),
    ]);
  });

  test('a WSL session: VS Code through WSL, on the Linux folder', () {
    expect(revealSteps(origin: AgentOrigin.external, host: AgentHost.wsl, cwd: '/home/a/p'), [
      const OpenInVsCode(['--remote', 'wsl+Ubuntu', '/home/a/p']),
    ]);
    expect(revealSteps(origin: AgentOrigin.mikky, cwd: r'\\wsl.localhost\Debian\home\a\p'), [
      const OpenInVsCode(['--remote', 'wsl+Debian', '/home/a/p']),
    ]);
    expect(revealSteps(origin: AgentOrigin.mikky, host: AgentHost.wsl, cwd: '/mnt/c/p', distro: 'Arch'), [
      const OpenInVsCode(['--remote', 'wsl+Arch', '/mnt/c/p']),
    ]);
  });

  test('SessionOrigin reads what mikkyd keeps', () {
    final o = SessionOrigin.fromJson({
      'windowPid': 12,
      'windowHandle': 34,
      'windowExe': 'Code.exe',
      'termProgram': 'vscode',
      'vscodePid': '12',
      'cwd': r'C:\p',
      'agent': 'claude',
      'wtSession': 3,
    });
    expect(
      (o.windowPid, o.windowHandle, o.windowExe, o.termProgram, o.vscodePid, o.cwd, o.wtSession),
      (12, 34, 'Code.exe', 'vscode', '12', r'C:\p', null),
    );
  });

  test('VS Code is found on the PATH, else where its installers put it', () {
    final files = {r'C:\Users\a\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd'};
    bool exists(String p) => files.contains(p);
    expect(
      findVsCode(
        environment: {'PATH': r'C:\Windows;C:\Users\a\AppData\Local\Programs\Microsoft VS Code\bin'},
        exists: exists,
        windows: true,
      ),
      r'C:\Users\a\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd',
    );
    expect(
      findVsCode(
        environment: {'PATH': r'C:\Windows', 'LOCALAPPDATA': r'C:\Users\a\AppData\Local'},
        exists: exists,
        windows: true,
      ),
      r'C:\Users\a\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd',
    );
    expect(findVsCode(environment: {'PATH': r'C:\Windows'}, exists: exists, windows: true), isNull);
    expect(
      findVsCode(environment: {'PATH': '/usr/bin'}, exists: (p) => p == '/usr/bin/code', windows: false),
      '/usr/bin/code',
    );
  });
}
