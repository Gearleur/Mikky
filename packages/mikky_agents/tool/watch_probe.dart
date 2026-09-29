// A0 probe: does Directory.watch see changes made inside WSL?
import 'dart:io';

void main(List<String> argv) async {
  final dir = Directory(argv.first);
  final sub = dir.watch(recursive: true).listen((e) => stdout.writeln('event ${e.type} ${e.path}'));
  stdout.writeln('watching ${dir.path}');
  await Future<void>.delayed(Duration(seconds: int.parse(argv[1])));
  await sub.cancel();
  exit(0);
}
