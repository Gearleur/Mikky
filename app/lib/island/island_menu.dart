import 'package:mikky_engine/mikky_engine.dart';

import '../overlay/overlay_channel.dart';
import '../settings.dart';
import '../theme.dart';

/// Each entry of the island's menu (a right click, the notification area,
/// the star of the small window).
enum IslandMenuItem {
  themeAuto,
  themeDark,
  themeLight,
  edgeTop,
  edgeRight,
  demoScenario,
  demoAdd,
  demoStop,
  tuning,
  notifications,
  sound,
  volumeLow,
  volumeMid,
  volumeHigh,
  hotkeys,
  autoRelaunch,
  hooksClaude,
  hooksCodex,
  autostart,
  stopAll,
  quit;

  /// Its id in a [MenuEntry] (never 0: the separator's).
  int get id => index + 1;

  static IslandMenuItem? byId(int? id) => id == null || id < 1 || id > values.length ? null : values[id - 1];

  static const themes = {themeAuto: ThemeChoice.auto, themeDark: ThemeChoice.dark, themeLight: ThemeChoice.light};
  static const volumes = {volumeLow: .2, volumeMid: .5, volumeHigh: 1.0};
}

/// The menu's entries, checked as [settings] says.
List<MenuEntry> islandMenuEntries({
  required Settings settings,
  required bool demo,
  required bool canLaunch,
  required bool autostart,
  required bool autoRelaunch,
}) {
  final s = settings;
  MenuEntry entry(IslandMenuItem item, String label, {bool checked = false}) =>
      MenuEntry(item.id, label, checked: checked);
  return [
    entry(IslandMenuItem.themeAuto, 'Thème : automatique', checked: s.theme == ThemeChoice.auto),
    entry(IslandMenuItem.themeDark, 'Thème : noir', checked: s.theme == ThemeChoice.dark),
    entry(IslandMenuItem.themeLight, 'Thème : blanc', checked: s.theme == ThemeChoice.light),
    const MenuEntry.separator(),
    entry(IslandMenuItem.edgeTop, 'Position : en haut', checked: s.edge == IslandEdge.top),
    entry(IslandMenuItem.edgeRight, 'Position : à droite', checked: s.edge == IslandEdge.right),
    const MenuEntry.separator(),
    entry(IslandMenuItem.demoScenario, demo ? 'Démo : relancer le scénario' : 'Démo : lancer le scénario'),
    entry(IslandMenuItem.demoAdd, 'Démo : ajouter un agent'),
    if (demo) entry(IslandMenuItem.demoStop, 'Démo : arrêter (retour aux vrais agents)'),
    entry(IslandMenuItem.tuning, 'Réglage de Mikky…'),
    entry(IslandMenuItem.notifications, 'Notifications', checked: s.notifications),
    entry(IslandMenuItem.sound, 'Sons', checked: s.sound),
    if (s.sound) ...[
      entry(IslandMenuItem.volumeLow, 'Volume : bas', checked: s.volume <= .3),
      entry(IslandMenuItem.volumeMid, 'Volume : moyen', checked: s.volume > .3 && s.volume < .8),
      entry(IslandMenuItem.volumeHigh, 'Volume : fort', checked: s.volume >= .8),
    ],
    entry(IslandMenuItem.hotkeys, 'Raccourcis Ctrl + Alt (A, Espace, M)', checked: s.hotkeys),
    // Agents stopped by a subscription's limit relaunched by themselves
    // (« Ensorcelé »); the violet star after « Agents » while on.
    entry(IslandMenuItem.autoRelaunch, 'Relance automatique', checked: autoRelaunch),
    if (canLaunch) ...[
      entry(IslandMenuItem.hooksClaude, 'Hooks Claude Code…'),
      entry(IslandMenuItem.hooksCodex, 'Hooks Codex…'),
      entry(IslandMenuItem.autostart, 'Moteur au démarrage de Windows', checked: autostart),
    ],
    const MenuEntry.separator(),
    if (canLaunch) entry(IslandMenuItem.stopAll, 'Arrêter tous les agents de Mikky…'),
    entry(IslandMenuItem.quit, 'Fermer Mikky · les agents continuent'),
  ];
}
