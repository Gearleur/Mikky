# Mikky — où on en est

Mis à jour le 2026-10-04 · branche `main` · https://github.com/Gearleur/Mikky

À lire en premier, avec `CLAUDE.md`. Le design est dans `design.md`, les idées dans `idees.md`, les specs validées dans `specs/`.

## Le cap

- Mikky est un petit chat noir dans une **île flottante** (overlay Windows), et un **compagnon d'agents** : il lance et suit Claude Code et Codex, comme un Paperclip plus simple. Abonnements seulement, pas de clé d'API, pas de harnais maison.
- **L'île est l'interface** (décision du 1er octobre). La grande fenêtre de suivi est reportée ; elle est gardée sur la branche `feature/r4-workspace`.
- **`mikkyd` (Rust) fait tout le travail d'agents** ; l'app Flutter n'est qu'un écran.
- **Priorité** : une île fiable, juste et légère. Ensuite : de nouveaux outils (R5), puis des agents qui se parlent (R6), puis le VPS (R7).

## Ce qui marche

- **Île** : overlay transparent avec clics traversants, forme SDF en shader, positions « en haut » et « à droite ». À droite, la petite île montre Mikky dans l'état de l'agent qu'il suit. Ce qui attend l'utilisateur sort dans une bulle gluante. Quand un agent a fini, la petite île sort 5,2 s. Au survol, l'île s'ouvre en petite fenêtre. 0 % de CPU quand l'île est cachée.
- **Petite fenêtre** :
  - accueil en applications (2026-10-02) : en haut et à droite, des pages de tuiles, une par agent ; une tuile ouvre l'agent, les outils un nouvel agent ;
  - page d'un agent (un seul fil : messages et actions de chaque tâche ensemble, depuis le 2026-10-05), nouvel agent (Windows ou WSL, Demander / Auto), connexion ;
  - menu étoile ; Oui / Non / Toujours, questions ; pause, reprise, arrêt ;
  - ranger les sessions, « Ensorcelé » (relance après la limite) ;
  - notifications Windows.
- **Mikky compagnon** (2026-10-04, fonctionnel, visuel à refaire) : il réagit à chaque agent (geste, émote, son), s'endort et se réveille ; il **apporte chaque demande avec son contexte** (tâche, étape, derniers mots, dernières actions +N −M) ; sons (Media Foundation + XAudio2), raccourcis Ctrl + Alt + A / Espace / M.
- **Hooks Claude Code et Codex** (2026-10-04) : les sessions lancées dans un terminal ou VS Code demandent aussi leurs permissions dans Mikky (`mikky-hook` → `mikkyd`) ; installation avec diff, jamais sans l'utilisateur. **Pas encore installés chez l'utilisateur.**
- **`mikkyd`** :
  - lance les adaptateurs ACP sous Windows ou dans WSL (job object) ;
  - garde permissions et questions même sans écran ;
  - lit les sessions de Claude et de Codex, y compris celles lancées ailleurs ;
  - SQLite, protocole 3, WebSocket sur 127.0.0.1 avec un jeton gardé dans le coffre de Windows ;
  - un moteur natif dans WSL.
  - Fermer l'app n'arrête pas les agents.
- **Planches** (`--kit`, la référence visuelle) : Marque, Composants, Petite île, Accueil Top, Accueil Right, Agent, Messages, Technique.

## 5 octobre (suite) : le notch remplace l'accueil du haut

- Planches Notch Top et Notch Right faites avec l'utilisateur ; il a choisi **« Côte à côte »** pour le haut, appliqué dans l'app : `HomeView` en haut = le notch 730 × 216 (`design.md`, « Notch »). L'ancienne planche Accueil Top et la ligne de métro (`metro.dart`) sont supprimées. La droite garde l'accueil de la planche Accueil Right ; ses essais de notch (Au centre, En-tête, Dock) **attendent un choix**.
- **Le logiciel d'une tâche** (`AgentApp` : VS Code, Terminal, Claude, Codex, Mikky) : `mikkyd` le lit (`entrypoint` de Claude, `originator` de Codex) et l'envoie dans l'événement `session` (`app`). Le moteur Windows a été relancé sur le bundle `Mikky-20261005-154738` (aucun agent actif, vérifié) ; le moteur natif de WSL reste celui du 1er octobre.
- Vérifié en vrai : le notch s'ouvre à 730 px, Mikky suit la session VS Code en cours, ses étapes en direct, « VS Code » au-dessus du titre et le signe `</>` sur les tuiles des sessions VS Code. Après les applications, « + Nouvelle tâche » puis un petit point à chaque place libre.

## 5 octobre : un seul fil sur la page d'un agent

- Demande de l'utilisateur : une tâche lancée dans VS Code ne montrait pas la réponse de Claude ; le chat et les actions doivent être au même endroit. Pour une session extérieure qui travaille, il n'y avait pas de champ, donc pas de bascule : la page restait sur la ligne de métro, sans messages.
- **Suivi et Chat remplacés par un seul fil** (`threadOf`, `session_views.dart`) : chaque tâche déroule dans l'ordre ce que l'agent dit, ses actions groupées (code en direct sous l'action en cours), les messages glissés ; sa réponse dessous. Logique pure : `turnFlow`, `turnAnswer`, `planSteps`, `toolSteps` (`session_steps.dart`). Planches Agent, Messages, Accueil Top / Right à jour. **À valider sur les planches.**
- `mikkyd` : le résumé que Claude écrit après une compaction (`isCompactSummary`) n'est plus pris pour un message de l'utilisateur (il coupait la tâche en deux). **Le moteur en service doit être reconstruit et relancé** (sans agent actif) pour en profiter.

## Session du 4 octobre : Mikky au centre, le fonctionnel

Comparaison avec Coucou (`~/projects/coucou`, MIT) : Mikky avait le moteur de Mochi (états, émotes), mais l'app n'en branchait presque rien, et les demandes arrivaient sans contexte. Demande de l'utilisateur : **le fonctionnel seulement** ; les animations et les sons se refont avec lui demain, une par une. **Seul l'accueil est validé.**

- **Moteur** (`mikky_engine`) : `reactions.dart` (table événement → état, émote, geste, son `MikkyCue`, phrase ; `MikkyDirector` : une réaction par changement d'agent, sommeil après 10 min) ; `brief.dart` (`TaskBrief`, `activityOf`, `diffStat`) ; Mikky : `slap`, `onSound`. L'île ouverte pour une demande, en haut : 450 × 260.
- **App** : `BriefView` (en haut dans l'île, à droite page « Pour toi », `SideApp.openAlert`) ; `SoundBoard` (`app/lib/sound/`) et lecteur natif (`app/windows/runner/sound.cpp`) ; menu : Sons, Volume, Raccourcis, Hooks Claude Code…, Hooks Codex… ; page `HooksPage`.
- **Sons** : les MP3 PSP de l'utilisateur dans `app/assets/sounds/`, **hors de git** (dépôt public, sons de Sony). MCI ne lit pas ces MP3 (DirectShow refuse leur encodage) : Media Foundation les décode.
- **Hooks** : `daemon/mikky-hook` (relais : coffre de Windows, 300 ms pour se connecter, rien écrit sans réponse, 110 s au plus) ; `mikkyd` : `hooks.rs` (file des demandes ; rien n'attend sans écran, ni pour ses propres sessions, ni pour les questions ; la suite de la session retire la demande), `claude_settings.rs` (installation Claude / Codex, diff, empreinte, copie datée, relais copié dans `%LOCALAPPDATA%\Mikky\bin`). Essai de bout en bout : `cargo test -p mikky-hook`.
- **Bundle** reconstruit et relancé (`dist\Mikky-20261004-222423`, sans agent actif) ; aperçu de l'installation vérifié sur le vrai `settings.json` (57 lignes ajoutées, rien retiré), **rien écrit**.
- **Plans** : `plans/2026-10-05-visuel-et-son.md` (la séance de demain : animations une par une, sons, écrans pas revus, planches à ajouter) ; `plans/2026-10-05-plateforme.md` (ton environnement, performance, sécurité, cloud et versions V1 → V5).

## Session du 2 octobre : le nouvel accueil

- Les maquettes HTML de `docs/notch_haut/` (Top 1 × 4 et 2 × 4, Right 2 × 2 et 3 × 3) servent seulement de référence visuelle ; rien n'en est repris techniquement.
- Planches **Accueil** et **Accueil haut** retirées (le rail « Mikkys au travail » aussi) ; « Choisir le lieu » corrigé et renommé **« Choisir l'environnement »**, sur la planche Composants.
- Planche Composants, sections « Accueil · … » : environnement, modes (nos onglets mini), outils sortis du bord, tuiles, pages, Mikky vivant ; variantes de la maquette (choix et flèches en noir) à côté, pour comparer.
- Nouvelles planches **Accueil Top** (450 × 260, hauteur validée) et **Accueil Right** (344 × 520, 6 applications par page, pages de côté) : une seule vue, `HomeView`, deux dispositions (`HomeLayout`). Modes en noir, flèches grises. Une application = un ou plusieurs agents qui font une tâche.
- Planche Composants rangée par catégories, les plus utilisés d'abord, avec un sélecteur ; les couleurs de l'interface y sont passées.
- **Dans l'app** : l'ancien accueil (`HomePage`) est remplacé à droite (`HomeScreen`) et en haut (l'île ouverte par l'utilisateur). Le Mikky de l'île se pose à sa place dans l'accueil.
- **Ensuite, même jour** : on garde 8 applications en haut. Le haut utilise la même fenêtre que la droite (`SideApp` avec `HomeLayout.top`) : une tuile ouvre la page de l'agent (Suivi / Chat) et l'île grandit à 450 × 380 (`IslandLayout.page`, fenêtre 560 × 480). Le mode **Chat** de l'accueil est l'ancien « Nouvel agent » ; « + » et les outils y mènent, en haut aussi. L'**historique** (bouton en bas à gauche, feuille par-dessus, recherche dans les titres) est branché ; un agent rouvert revient parmi les applications. Planches Accueil Top et Right : sections Chat et page d'un agent.
- **Puis** : à droite, l'accueil est la version verticale du haut (290 × 408, 8 applications de 64 px en 2 × 4), et grandit à 344 × 520 pour la page d'un agent. Coins de l'île ouverte ronds comme les planches. Tuiles : un agent fini (inactif) est vert. **Limite Codex** : codex-acp la renvoie en « Internal error » avec le détail dans `data` ; `mikkyd` la lit maintenant (essai réel, limite de la semaine « Oct 5th, 2026 9:47 AM », lue aussi). **Le moteur `mikkyd` en service doit être reconstruit et relancé** (sans agent actif) pour que la limite Codex arrive en jaune.
- Détails et décisions : `design.md` §7 « Nouvel accueil ».

## Session précédente (1er octobre)

- **Essai réel Codex, 1er octobre** : lancement, réponse « ok », fermeture/reconnexion de l'écran et arrêt confirmé par `runs.list` sous Windows et WSL, avec le moteur Rust et les adaptateurs de production. Sous Windows et WSL, une écriture demandée en mode « Demander » est restée en attente après reconnexion ; le refus a été transmis et aucun fichier n'a été créé. Claude n'a pas été essayé (limite d'usage de l'utilisateur).
- **PID WSL à déployer** : le backend Linux actuellement en service vient d'un ancien bundle et ne renvoie pas encore `adapterPid`. Le PID Windows est confirmé. Mettre à jour le binaire Linux et redémarrer son daemon seulement après avoir vérifié qu'il ne pilote aucun agent actif.
- L'île et l'accueil suivent la même règle pour ce qui attend : plus d'étoile rouge qui reste.
- La limite de Codex est reconnue (« Limite atteinte », 100 %), et les limites sont en haut de l'accueil.
- Il ne reste que cinq états : travaille, « ! » attend, « ! » rouge erreur, limite, terminé ; rien en pause. Le violet ne sert plus qu'à « Ensorcelé ».
- Menu étoile : une seule étoile visible ; « Supprimer… » ouvre la confirmation sur place.
- Plus de trou blanc dans l'accueil ; l'ombre de l'île n'est plus carrée.

## À valider avec l'utilisateur

- **Dans l'app** : la bulle, la petite île à la fin d'un agent, la confirmation de suppression.
- **Choix en attente** (`design.md` §12) : l'animation de Claude au travail, l'accueil épuré.
- **Nouvelle exploration UI/UX** (`idees.md` §9) : juste milieu mascotte/outil professionnel, accueil en tuiles inspiré de Cocoon et iiSU, réglages dédiés, vue Agent/Consommation et Projets. La direction actuelle en lignes plates reste la référence tant qu'une variante n'a pas été choisie sur les planches.

## Prochaines étapes, dans l'ordre

**Périmètre du MVP** : une île Windows fiable pour voir les sessions locales de Claude Code et Codex, lancer et piloter des agents sur Windows ou WSL, répondre aux permissions et retrouver les agents après fermeture de l'écran. Ne pas promettre qu'une session extérieure « tourne » tant que son processus n'a pas été vérifié : le JSONL prouve une activité, pas la vie d'un processus.

**Demain (5 octobre) : le visuel et le son, avec l'utilisateur** : `plans/2026-10-05-visuel-et-son.md` (les animations de Mikky une par une, les sons un par un, la carte de demande en haut et à droite, la page Réglages qui remplace le menu du clic droit). Puis l'essai réel des hooks et la suite technique : `plans/2026-10-05-plateforme.md` §6.

**Le menu du clic droit** (les réglages de Mikky) : depuis que c'est notre menu flottant dans l'accueil, il est devenu grand et « trop gluant, bouncy, perturbant » (l'utilisateur, 2026-10-02) ; il a encore grandi le 4 (sons, raccourcis, hooks). À reprendre sur les planches : une vraie page Réglages.

**Étape suivante : les applications** (design d'abord, sur les planches). Ce qu'il y a dans une tuile (images), comment valider ses **actions rapides** depuis l'accueil, et tout ce que faisait l'ancien accueil, à refaire (en attendant : la page de l'agent, en haut comme à droite) :
- **Approbation** : Oui / Non / Toujours sous l'agent qui attend, la commande en pilule ; les **questions** (« Pose une question : … », formulaire) ; Y / N au clavier en haut.
- **Erreur** : « ! » rouge, « Marquer l'erreur comme réglée ».
- **Limite de l'abonnement** : « Limite atteinte · reprend à 17 h 10 », **« Terminer »** et **« Relance auto »** ; **Ensorcelé** (« se relance à 17 h 11 », étoile violette, « Terminer » pour refuser) ; la **relance automatique pour tous** (réglage, étoile violette après « Agents »).
- **Pause** : « En pause », « Reprendre ».
- **Limites de l'abonnement Codex** (« 69 % des 5 h, repart à 17 h 10 · 70 % de la semaine »), en haut de l'ancien accueil.
- **Groupes** En attente / Travaillent / Terminés / Historique / Archives, repliables ; épinglés d'abord ; les 5 terminés les plus récents, le reste en historique.
- **Menu d'un agent** (étoile grise ou clic droit sur la ligne) : pause / reprendre, arrêter, VS Code, dossier, renommer, épingler, archiver, supprimer (avec la confirmation sur place).
- **Sessions extérieures** (« session extérieure »), WSL nommé sur la ligne, heures courtes.
- L'**étoile des réglages** (aujourd'hui : clic droit), l'état vide. (Le nouvel agent : fait, le Chat de l'accueil.)
- Aussi : « Choisir l'environnement » branché sur l'hôte du nouvel agent (Local = Windows, WSL), VPS et Cloud plus tard ; la recherche de l'historique par `mikkyd` (dossiers, ce qui a été dit).

**Prochain chantier UI en parallèle du cœur MVP** : sur les planches, poser la navigation et une vraie page Réglages ; comparer ensuite trois accueils (lignes, tuiles, hybride) dans l'île en haut et à droite, puis dessiner Agent/Consommation et Projets. Les lieux Windows/WSL/VPS/Replicas sont d'abord des propriétés et filtres des agents/projets. Détails et références dans `idees.md` §9.

1. **Fiabiliser le parcours réel** : Codex a passé le lancement, un tour simple, la reconnexion de l'écran, l'arrêt et une permission refusée sous Windows et WSL. Restent les questions, la pause, la vérification des processus enfants, la vraie reprise d'une session Windows, plusieurs agents et demandes simultanées, puis Claude après la fin de sa limite. Rejouer les tests automatisés et documenter chaque échec reproductible.
2. **Dire et vérifier ce qui tourne** : distinguer dans l'interface un run contrôlé par `mikkyd` d'une session extérieure observée dans les fichiers. Les libellés des sessions extérieures et le PID de l'adaptateur ACP possédé par Mikky sont en place. Prochaine étape : vérifier la vie de ce processus et de ses enfants, puis étudier l'association fiable entre session extérieure et processus Windows/WSL. Ne proposer arrêt et permissions que lorsque Mikky contrôle réellement l'agent.
3. **Borner la mémoire de `mikkyd`** : résumés par session, événements et détail paginés à la demande, limites de backlog et de files d'envoi ; mesurer un long chat et plusieurs sessions. La petite île au repos est passée de 56 à 28 images par seconde (`--bench`) ; mesurer aussi l'île ouverte, les flous et le CPU caché (`--perf`).
4. **Soigner l'installation et la distribution** : vérifier le bundle Windows + binaire WSL, les dépendances et les mises à jour des adaptateurs, les erreurs et la reprise après échec ; ajouter une vérification de build et un parcours d'installation reproductible. S'inspirer de Coucou pour prévisualiser, sauvegarder et désinstaller proprement toute modification de configuration d'un outil.
5. **Étudier des hooks Claude optionnels pour les sessions extérieures** : recevoir leurs événements et, si le protocole le permet, leurs permissions sans lancer l'agent depuis Mikky. Préserver les autres hooks, gérer plusieurs sessions et demandes à la fois, et laisser Claude suivre sa voie normale si Mikky est fermé. Garder ACP pour les agents lancés par Mikky et la lecture JSONL pour l'historique. Étudier séparément une solution équivalente pour Codex.
6. **Faire évoluer SQLite sans changer de moteur** : `mikky.db` contient aujourd'hui une seule ligne d'état JSON, suffisante pour les métadonnées du MVP. Ajouter des migrations et des tables indexées quand les sessions, les événements et la mémoire deviennent interrogeables ; sauvegarde cohérente avec WAL et restauration vérifiée. DuckDB ne devient utile que si de vraies analyses volumineuses apparaissent.
7. **Mémoire utilisateur locale, après le MVP** : historique recherchable (FTS), souvenirs retenus avec source, date, périmètre, correction et suppression. Les agents passent par une API de `mikkyd` avec des droits explicites, jamais directement par le fichier SQLite ; ne leur envoyer que les éléments pertinents. Préserver cette API pour un hébergement futur. Un `mikkyd` personnel sur VPS peut encore utiliser SQLite ; choisir une base serveur si un service multi-utilisateur l'exige.
8. **Relance automatique dans Rust**, si elle doit marcher sans écran (aujourd'hui, fermer l'app la suspend). Tester reprise et annulation après redémarrage.
9. **R5, nouveaux outils** : OpenCode, pi, OpenClaw, Gemini CLI. Garder les harnais qui marchent avec un abonnement sans clé et vérifier leur ACP. **R6, agents qui se parlent** : rechercher A2A, MCP, Agora et MAST, puis définir identités, droits et journal avant le canal.
10. **Finition après le cœur** : accessibilité, réglages et découverte des fonctions, puis fonctions à choisir dans `idees.md` §7 (routines, boîte de réception, pièces jointes, LocalSend, dictée…). Coucou donne des pistes pour l'accueil, les sons et les intégrations ; les ajouter seulement après validation du parcours d'agent.

Reportés : R4, la grande fenêtre (branche `feature/r4-workspace`) ; R7, le VPS par tunnel SSH et les agents entre machines.

## Le code

```
daemon/                  Rust : mikky-acp (JSON-RPC ACP), mikkyd (agents, sessions, SQLite, API,
                         hooks.rs, claude_settings.rs), mikky-hook (relais des hooks)
packages/mikky_engine/   Dart pur : Mikky (reactions.dart), règles de l'île (IslandMachine),
                         SessionLog, brief.dart (ce que Mikky apporte), groupes
packages/mikky_agents/   client de mikkyd (DaemonClient, RealAgentSource, AgentStore, HookAsk)
app/lib/island/          l'île (island_view, compact_view = petite île, content/brief_view),
                         shader app/shaders/island.frag
app/lib/side/            petite fenêtre : accueil (side_app), agent_page, brief_page, hooks_page, session_*
app/lib/sound/           sound_board.dart : quel fichier pour quel signal
app/lib/ui/              composants, pixels (pixel_fx), menu flottant
app/lib/boards/          planches --kit ; images de test dans app/test/goldens/
app/windows/runner/      overlay natif (clics traversants, crochet souris, menus, raccourcis
                         globaux, sons : sound.cpp)
```

Mikky écrit dans `%APPDATA%\Mikky\` (réglages, réglage de Mikky). Les adaptateurs sont dans `%LOCALAPPDATA%\Mikky\acp`, et dans WSL dans `~/.local/share/mikky`. Le relais des hooks, une fois installés, dans `%LOCALAPPDATA%\Mikky\bin`. Aucun identifiant sur disque. Les sons (`app/assets/sounds/*.mp3`) ne sont pas dans git : les copier à la main sur une autre machine.

## Lancer, tester

- **Construire** : `.\scripts\Build-Windows.ps1` crée `dist\Mikky-<date>` (le bundle entier, `mikkyd` compris).
- **Lancer** : `.\Start-Mikky.ps1`, et `-Boards` pour les planches.
- **Relancer** : `Stop-Process -Name mikky; .\Start-Mikky.ps1`. Ajouter `, mikkyd` après `mikky` si le Rust a changé, et seulement si aucun agent lancé par Mikky ne tourne.
- **Tests** :
  - `cargo test` dans `daemon/` ;
  - `C:\dev\flutter\bin\dart.bat test` dans chaque paquet ;
  - `flutter.bat test` dans `app/` ;
  - pour les images : `flutter.bat test --update-goldens test/boards_test.dart`, **puis les regarder**.
- **Mesure de l'île** : `mikky.exe --bench`, ou `--bench --fast` pour l'ancien rythme à 60 images par seconde. L'île sort avec un faux agent ; Mikky compte les images entre 4 et 16 s, les écrit dans `%TEMP%\mikky-bench.txt`, puis se ferme. Arrêter l'île ouverte d'abord. Le CPU mesuré de l'extérieur ne veut rien dire quand Windows ne cadence pas la fenêtre (île cachée, écran éteint).
- **Diagnostic** : `dart run tool/state_check.dart` dans `packages/mikky_agents` compare ce que voit l'île et ce que voit l'accueil (lecture seule). `tool/smoke.dart` essaie de vrais agents : ça coûte deux messages, et il faut supprimer les sessions qu'il laisse.
- **Essai réel Codex sans Claude** : dans `packages/mikky_agents`, `dart run tool/backend_smoke.dart --codex-only` lance un court tour sous Windows et WSL, ferme/reconnecte l'écran et vérifie l'arrêt des runs qu'il a créés. `dart run tool/codex_permission_smoke.dart` vérifie une permission Windows, la reconnexion et le refus sans écrire de fichier ; ajouter `--wsl` pour le même essai sous WSL. Ces essais créent des sessions dans l'historique de Codex.

## Pièges utiles

- **Travail à plusieurs** : d'autres sessions modifient les mêmes fichiers. N'enregistrer que ses lignes ; pour un fichier partagé, passer par `git hash-object -w` puis `git update-index --cacheinfo`.
- **Inventaire de Rust** : il arrive comme des mises à jour, au démarrage et après une reconnexion. Une session n'est « nouvelle » que si elle a été écrite après `follow()`.
- **Codex change son format** : la limite est arrivée dans `task_complete.error`, et des compteurs vides (« premium ») sont apparus. Regarder les vrais fichiers dans `~/.codex/sessions`.
- **Flutter** : donner une clé aux listes dont des éléments apparaissent ou disparaissent. `late final` avec un initialiseur qui démarre quelque chose : le créer dans `initState`.
- **WSL** :
  - lancer avec `bash -l` ;
  - un script de plusieurs lignes passe par l'entrée de `bash -s` ;
  - `wsl.exe` écrit en UTF-16 ;
  - donner le chemin Linux à la session ;
  - remplacer un binaire ELF par renommage, jamais en l'écrasant.
- **Git Bash** convertit les chemins (`MSYS_NO_PATHCONV=1`). Pour les gros remplacements, écrire un script Python dans un fichier plutôt qu'un heredoc.
- **Dart** :
  - un flux `broadcast(sync: true)` repasse dans l'envoi en cours ;
  - `future.whenComplete(() => map.remove(k))` s'attend lui-même ;
  - écrire `\$HOME` dans une chaîne.
- **Tests qui dépendent du temps** : ceux qui suivent des fichiers (`session_watcher_test`, `daemon_watcher_test`) échouent parfois quand toute la suite tourne ; les relancer seuls avant de chercher un bug.
- **Ne jamais piloter la souris ou le clavier** pendant que l'utilisateur utilise le PC.
