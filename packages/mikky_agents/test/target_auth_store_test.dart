import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart' hide SessionWatcher, WatchedSession;

import '../tool/legacy/legacy.dart';

import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  group('targets', () {
    final wsl = WslTarget();

    test('a folder tells where the agent runs', () {
      expect(hostOfFolder(r'C:\Users\user\projet'), AgentHost.windows);
      expect(hostOfFolder('/home/user/projet'), AgentHost.wsl);
      expect(hostOfFolder(r'\\wsl.localhost\Ubuntu\home\user'), AgentHost.wsl);
      expect(hostOfFolder(r'\\wsl$\Ubuntu\home\user'), AgentHost.wsl);
    });

    test('paths between Windows and WSL', () {
      expect(wsl.linuxPath(r'C:\Users\user\projet'), '/mnt/c/Users/user/projet');
      expect(wsl.linuxPath(r'\\wsl.localhost\Ubuntu\home\user\x'), '/home/user/x');
      expect(wsl.linuxPath('/home/user'), '/home/user');
      expect(wsl.windowsPath('/home/user/.claude'), r'\\wsl.localhost\Ubuntu\home\user\.claude');
      expect(wsl.windowsPath('/mnt/d/jeux'), r'D:\jeux');
      expect(WindowsTarget().windowsPath(r'C:\x'), r'C:\x');
    });

    test('bash quoting', () {
      expect(shellQuote('/home/user/x.js'), '/home/user/x.js');
      expect(shellQuote("l'essai"), r"'l'\''essai'");
      expect(shellQuote(r'$HOME'), r"'$HOME'");
    });
  });

  group('sign-in', () {
    test('claude auth status', () {
      final s = parseClaudeStatus(0, '{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "pro"}');
      expect(s.installed, isTrue);
      expect(s.loggedIn, isTrue);
      expect(s.plan, 'pro');
      expect(parseClaudeStatus(1, '{"loggedIn": false}').loggedIn, isFalse);
      expect(parseClaudeStatus(127, '').installed, isFalse);
    });

    test('codex login status', () {
      expect(parseCodexStatus(0, 'Logged in using ChatGPT').plan, 'ChatGPT');
      expect(parseCodexStatus(1, 'Not logged in').loggedIn, isFalse);
      expect(parseCodexStatus(1, 'Not logged in').installed, isTrue);
      expect(parseCodexStatus(127, 'bash: codex: command not found').installed, isFalse);
    });

    test('the device code, through the terminal noise', () {
      const out =
          '\x1B[1mFollow these steps\x1B[0m\r\n'
          '1. Open this link in your browser and sign in to your account\r\n'
          '   \x1B[94mhttps://auth.openai.com/codex/device\x1B[0m\r\n'
          '2. Enter this one-time code (expires in 15 minutes)\r\n'
          '   \x1B[94m4NSL-UKITR\x1B[0m\r\n';
      final p = parseLoginPrompt(stripAnsi(out))!;
      expect(p.url, 'https://auth.openai.com/codex/device');
      expect(p.code, '4NSL-UKITR');
      // The link alone is not enough for Codex: wait for the code.
      expect(parseLoginPrompt('https://auth.openai.com/codex/device\n2. Enter'), isNull);
      expect(parseLoginPrompt('Opening https://claude.ai/oauth/authorize?x=1 in your browser')!.code, isNull);
    });
  });

  group('store', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('mikky_store'));
    tearDown(() async => tmp.delete(recursive: true));

    test('keeps agents, recent folders and choices', () async {
      final store = AgentStore(File('${tmp.path}/agents.json'));
      store.put(
        StoredAgent(
          id: 'a1',
          provider: AgentProvider.codex,
          host: AgentHost.wsl,
          cwd: '/home/user/p',
          permissions: PermissionMode.auto,
          createdAt: DateTime.utc(2026, 9, 29),
          sessionId: 's1',
          title: 'Tests',
        ),
      );
      for (var i = 0; i < 10; i++) {
        store.usedFolder('/p$i', const LaunchChoice(provider: AgentProvider.claude, host: AgentHost.wsl, permissions: PermissionMode.ask));
      }
      store.usedFolder('/p3', const LaunchChoice(provider: AgentProvider.codex, host: AgentHost.wsl, permissions: PermissionMode.auto));
      await store.save();

      final again = AgentStore(store.file);
      await again.load();
      expect(again.bySession('s1')!.title, 'Tests');
      expect(again.bySession('s1')!.provider, AgentProvider.codex);
      expect(again.recentFolders, hasLength(AgentStore.maxRecentFolders));
      expect(again.recentFolders.first, '/p3');
      expect(again.choices['/p3']!.permissions, PermissionMode.auto);
    });

    test('a broken file is set aside', () async {
      final file = File('${tmp.path}/agents.json')..writeAsStringSync('{ pas du json');
      final store = AgentStore(file);
      await store.load();
      expect(store.agents, isEmpty);
      expect(File('${file.path}.broken').existsSync(), isTrue);
    });
  });
}
