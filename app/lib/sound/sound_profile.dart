import 'dart:convert';

import 'package:mikky_engine/mikky_engine.dart';

/// Immutable cue-to-asset data. Asset identifiers follow the native MP3
/// reader's contract; null intentionally silences a cue.
class SoundProfile {
  SoundProfile._(Map<MikkyCue, String?> files) : files = Map.unmodifiable(files);

  factory SoundProfile.silent() => SoundProfile._({for (final cue in MikkyCue.values) cue: null});

  factory SoundProfile.decode(String source, {SoundProfile? defaults}) {
    final json = jsonDecode(source);
    if (json is! Map<String, Object?>) throw const FormatException('Le profil sonore doit être un objet JSON.');
    return SoundProfile.fromJson(json, defaults: defaults);
  }

  factory SoundProfile.fromJson(Map<String, Object?> json, {SoundProfile? defaults}) {
    if (json['version'] is! int || json['version'] != 1) {
      throw const FormatException('Version de profil sonore non prise en charge.');
    }
    if (json.keys.any((key) => key != 'version' && key != 'sounds')) {
      throw const FormatException('Champ inconnu dans le profil sonore.');
    }
    final sounds = json['sounds'];
    if (sounds is! Map<String, Object?>) throw const FormatException('Le champ sounds doit être un objet.');
    final known = MikkyCue.values.asNameMap();
    final files = <MikkyCue, String?>{...?defaults?.files};
    for (final entry in sounds.entries) {
      final cue = known[entry.key];
      if (cue == null) throw FormatException('Événement sonore inconnu : ${entry.key}.');
      final value = entry.value;
      if (value != null && (value is! String || _asset.firstMatch(value)?.group(0) != value)) {
        throw FormatException('Son invalide pour ${entry.key} : nom MP3 sans extension attendu.');
      }
      files[cue] = value as String?;
    }
    for (final cue in MikkyCue.values) {
      if (!files.containsKey(cue)) throw FormatException('Événement sonore manquant : ${cue.name}.');
    }
    return SoundProfile._(files);
  }

  static final _asset = RegExp(r'^[a-z0-9_]{1,64}$');

  final Map<MikkyCue, String?> files;
  String? operator [](MikkyCue cue) => files[cue];
  Set<String> get assets => {for (final file in files.values) ?file};

  Map<String, Object?> toJson() => {
    'version': 1,
    'sounds': {for (final cue in MikkyCue.values) cue.name: files[cue]},
  };
}
