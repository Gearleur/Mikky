# Mikky — où on en est (pour reprendre)

Dernière mise à jour : 2026-09-29 · Dépôt : https://github.com/Gearleur/Mikky (branche `main`)

À lire en premier dans une nouvelle conversation, avec `CLAUDE.md`, la spec (`specs/2026-09-28-etape-1-design.md`) et le plan (`plans/2026-09-28-etape-1-plan.md`, section « Avancement »).

## 1. Ce qui marche (étape 1, sous Windows)

- **Overlay** : fenêtre transparente, toujours au premier plan, absente de la barre des tâches, clics traversants sauf sur l'île, hook souris global (`WH_MOUSE_LL`, 60 Hz max), 0 % de CPU île cachée. Code natif dans `app/windows/runner/flutter_window.cpp` (canal `mikky/overlay` : `setHitRect`, `setPlacement`, `showMenu`, `activate`, `quit`).
- **Île** : shader SDF (`app/shaders/island.frag`), thèmes noir « A » et blanc « pur », deux positions (en haut ; à droite en format téléphone), bulle séparée, trait de compte à rebours, contenu Focus (large en haut, portrait à droite).
- **Cerveau de l'île** : `IslandMachine` (règles 1 à 10 de la spec, sans timer, réveillée à `nextDeadline`) + `DemoAgentSource` (scénario : 3 agents, approbation, erreur, trois « terminé »), lancé au démarrage.
- **Mikky** : 11 états, 7 émotes, particules, badges, survol / immobile → amour / triple clic → sonné, et ses **transformations** (voir §3). Il prend l'état de l'agent en focus.
- **Menu** (clic droit sur l'île) : thème auto / noir / blanc, position en haut / à droite, Démo (relancer le scénario, ajouter un agent, tout arrêter), Réglage de Mikky…, Quitter. Choix gardés dans `%APPDATA%\Mikky\settings.json`.
- **Écran de réglage** : `mikky.exe --tuning` (fenêtre normale, processus séparé) : états, émotes, gestes, 8 curseurs de proportions enregistrés dans `%APPDATA%\Mikky\tuning.json`.
- **Tests** : 75 dans `packages/mikky_engine` ; goldens dans `app/test/goldens/` (`mikky_expressions_{light,dark}.png`, `mikky_forms.png`).

## 2. Lancer, tester, vérifier

- App : `C:\dev\flutter\bin\flutter.bat run -d windows` dans `app/`, ou `app\build\windows\x64\runner\Release\mikky.exe` après `flutter.bat build windows --release`. Écran de réglage : ajouter `--tuning`.
- Moteur : `C:\dev\flutter\bin\dart.bat test` dans `packages/mikky_engine`.
- Goldens : `C:\dev\flutter\bin\flutter.bat test --update-goldens test/mikky_expressions_test.dart` dans `app/`, puis **regarder les images** (c'est la façon la plus rapide de vérifier un changement visuel de Mikky).
- Vérif à l'écran : captures GDI avec `CAPTUREBLT`, souris simulée avec `SendInput` (pas `SetCursorPos`), prototypes rendus avec Chrome headless (voir `CLAUDE.md`).

## 3. Direction artistique validée par l'utilisateur (ne pas revenir dessus)

Les transformations : **c'est Mikky lui-même qui se transforme**, de façon organique et imparfaite, en gardant sa couleur, ses poils, et **le plus possible sa forme de base**. Tentatives rejetées : un vrai cœur (« trop cœur »), des boules bosselées, des piques, des brins fins, des touffes épaisses, trois boules pour « ••• ».

| Quoi | Ce qui a été validé |
|---|---|
| Amour | la mascotte **à peine** déformée en cœur (oreilles arrondies en lobes, bas en pointe douce), yeux contents, petits cœurs au-dessus des oreilles |
| Travaille | boule de poils = **la mascotte sans oreilles**, ses poils de base ressortant un peu plus tout autour ; pas de secousse ; redevient le chat de temps en temps (boule 6-9 s, chat 2,5-4 s) |
| Réfléchit | la même boule de poils, qui sautille ; redevient le chat de temps en temps (4-6 s / 2-3 s) |
| Attend ton feu vert | en boucle : 2 sauts en chat → « ! » sans yeux (barre large en haut, fine en bas, point bien séparé) pour 3-4 sauts → chat… ; pas de badge |
| Terminé | pas de roulade : petit saut un peu plus haut, yeux contents, une oreille plus grande, étincelles |
| Surpris | grands yeux ronds, oreilles très hautes |

Changement d'une forme à l'autre : mou comme de la gelée (ressort 95 / 0,38), toujours en repassant par le chat. Le code est dans `packages/mikky_engine/lib/src/mikky/` (`mikky.dart` : états, émotes, cycles ; `mikky_geometry.dart` : contour, formes, yeux).

## 4. Ce qui reste (prochaines étapes)

**Nouveau (2026-09-29)** : Mikky devient un compagnon d'agents. MVP choisi : lancer Claude et Codex depuis la fenêtre « à droite » et voir lequel travaille, LocalSend, classement des mails en local, tous les composants et animations designés d'avance. Détails et idées pour plus tard : `idees.md`. Maquette : `design/prototypes/composants.html` (à valider).

1. **Valider avec l'utilisateur** les expressions qui n'ont pas encore de transformation : question, erreur, limité, cherche, dort, sonné (et les oreilles rabattues). Idées proposées, non décidées : « ? » pour la question, s'affaisser pour l'erreur, se gonfler pour le terminé.
2. Figer les proportions validées dans `MikkyTuning` (et mettre à jour les goldens).
3. J3 : goutte de notification, points vivants du thème noir (uniformes déjà prévus dans le shader).
4. Idée pour plus tard : quand il y a plus de contenu, Mikky remonte en petit en haut à gauche et le nom disparaît (surtout à droite).
5. J5 : icône et menu dans la zone de notification (avec sous-menus Démo ▸), mesures finales. Masquer l'écran de réglage hors build de dev.
6. Étape 2 : brancher les vrais agents Claude Code (hooks, approbations qui répondent vraiment). `AgentSource` est l'interface prévue pour ça.

## 5. Pièges déjà rencontrés

- **`late final` + initialiseur qui démarre quelque chose** (ticker, canal) : jamais créé si personne ne le lit. Arrivé deux fois (canal au J0, ticker de l'écran de réglage). Créer dans `initState`.
- **Chaînes C++ avec accents** : le compilateur lit mal l'UTF-8 ; écrire `\u00e9`. L'outil d'édition convertit `\u2060` / `\u00e9` en vrai caractère : passer par un petit script Node si besoin.
- **PowerShell** met une virgule décimale dans les noms de fichiers (`burst-10,4.png`).
- **Contour de Mikky** : les courbes en cloche sur l'angle doivent « faire le tour » (`_bell`), sinon marche à la jointure (joue droite).
- La fenêtre de réglage lancée depuis un terminal s'ouvre derrière les autres fenêtres (normal).
- L'utilisateur utilise le PC pendant les tests : ses mouvements de souris peuvent fausser les tests automatiques (vérifier que le curseur est bien sur l'île avant de cliquer).

## 6. Mesures (release, 1920 × 1080 à 100 %, 12 cœurs)

Île cachée : 0 % · île ouverte animée : ~1 % du CPU total · mémoire : ~60 Mo (Gestionnaire des tâches).
