import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:test/test.dart';

/// PING.EXE processes aimed at [address] (a marker unique to the test).
Future<int> pings(String address) async {
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    "@(Get-CimInstance Win32_Process -Filter \"Name='PING.EXE' and CommandLine like '%$address%'\").Count",
  ]);
  return int.parse((r.stdout as String).trim());
}

void main() {
  test('stopping an agent ends the commands it started', () async {
    const address = '127.0.0.93';
    final target = WindowsTarget();
    // Like an adapter: it starts its child a moment later, once contained.
    final p = await target.start('powershell', ['-NoProfile', '-Command', 'Start-Sleep -Milliseconds 800; ping -n 60 $address']);
    target.contain(p);
    p.stdout.drain<void>();
    p.stderr.drain<void>();
    for (var i = 0; i < 50 && await pings(address) == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(await pings(address), 1);
    await target.kill(p);
    await p.exitCode.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await pings(address), 0);
  }, testOn: 'windows', timeout: const Timeout(Duration(seconds: 60)));
}
