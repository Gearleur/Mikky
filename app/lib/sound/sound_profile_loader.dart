import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sound_profile.dart';

const defaultSoundProfileAsset = 'assets/config/sounds.json';

/// Optional personal overrides, independent of the UI theme and volume.
File? get personalSoundProfile {
  final appData = Platform.environment['APPDATA'];
  return appData == null ? null : File('$appData/Mikky/sounds.json');
}

/// Read once before the island starts. An invalid personal file is rejected
/// as a whole, preserving the bundled profile and the user's file.
Future<SoundProfile> loadSoundProfile({AssetBundle? bundle, File? userFile, ValueChanged<String>? onWarning}) async {
  void warn(String message) => (onWarning ?? debugPrint).call(message);

  final SoundProfile defaults;
  try {
    defaults = SoundProfile.decode(await (bundle ?? rootBundle).loadString(defaultSoundProfileAsset));
  } catch (error) {
    warn('mikky: profil sonore intégré illisible, sons silencieux ($error)');
    return SoundProfile.silent();
  }
  final file = userFile ?? personalSoundProfile;
  if (file == null) return defaults;
  try {
    if (!await file.exists()) return defaults;
    return SoundProfile.decode(await file.readAsString(), defaults: defaults);
  } catch (error) {
    warn('mikky: profil sonore personnel ignoré, profil intégré conservé ($error)');
    return defaults;
  }
}
