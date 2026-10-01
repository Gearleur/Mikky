import 'package:mikky_engine/mikky_engine.dart';

/// Display/open-folder path conversion only. No process execution.
class WslPath {
  const WslPath({this.distro = 'Ubuntu'});
  final String distro;
  String windowsPath(String path) {
    if (!path.startsWith('/')) return path;
    final mount = RegExp(r'^/mnt/([a-z])(/.*)?$').firstMatch(path);
    if (mount != null) return '${mount[1]!.toUpperCase()}:${(mount[2] ?? '/').replaceAll('/', r'\')}';
    return '\\\\wsl.localhost\\$distro${path.replaceAll('/', r'\')}';
  }

  String linuxPath(String path) {
    final unc = RegExp(r'^\\\\wsl(?:\.localhost|\$)\\[^\\]+(\\.*)?$', caseSensitive: false).firstMatch(path);
    if (unc != null) return (unc[1] ?? r'\').replaceAll(r'\', '/');
    final drive = RegExp(r'^([A-Za-z]):(\\.*)?$').firstMatch(path);
    if (drive != null) return '/mnt/${drive[1]!.toLowerCase()}${(drive[2] ?? '').replaceAll(r'\', '/')}';
    return path;
  }
}

AgentHost hostOfFolder(String folder) {
  if (folder.startsWith('/') || RegExp(r'^\\\\wsl(\.localhost|\$)\\', caseSensitive: false).hasMatch(folder)) return AgentHost.wsl;
  return AgentHost.windows;
}
