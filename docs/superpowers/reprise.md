# Mikky — où on en est

Mis à jour le 2026-10-01 · branche `main` · https://github.com/Gearleur/Mikky

À lire en premier, avec `CLAUDE.md`. Le design est dans `design.md`, les idées dans `idees.md`, les specs validées dans `specs/`.

## Le cap

- Mikky est un petit chat noir dans une **île flottante** (overlay Windows), et un **compagnon d'agents** : il lance et suit Claude Code et Codex, comme un Paperclip plus simple. Abonnements seulement, pas de clé d'API, pas de harnais maison.
- **L'île est l'interface** (décision du 1er octobre). La grande fenêtre de suivi est reportée ; elle est gardée sur la branche `feature/r4-workspace`.
- **`mikkyd` (Rust) fait tout le travail d'agents** ; l'app Flutter n'est qu'un écran.
- **Priorité** : une île fiable, juste et légère. Ensuite : de nouveaux outils (R5), puis des agents qui se parlent (R6), puis le VPS (R7).

## Ce qui marche

- **Île** : overlay transparent avec clics traversants, forme SDF en shader, positions « en haut » et « à droite ». À droite, la petite île montre Mikky dans l'état de l'agent qu'il suit. Ce qui attend l'utilisateur sort dans une bulle gluante. Quand un agent a fini, la petite île sort 5,2 s. Au survol, l'île s'ouvre en petite fenêtre. 0 % de CPU quand l'île est cachée.
- **Petite fenêtre** :
  - accueil en groupes, limites Codex en haut ;
  - page d'un agent (Suivi / Chat), nouvel agent (Windows ou WSL, Demander / Auto), connexion ;
  - menu étoile ; Oui / Non / Toujours, questions ; pause, reprise, arrêt ;
  - ranger les sessions, « Ensorcelé » (relance après la limite) ;
  - notifications Windows.
- **`mikkyd`** :
  - lance les adaptateurs ACP sous Windows ou dans WSL (job object) ;
  - garde permissions et questions même sans écran ;
  - lit les sessions de Claude et de Codex, y compris celles lancées ailleurs ;
  - SQLite, protocole 3, WebSocket sur 127.0.0.1 avec un jeton gardé dans le coffre de Windows ;
  - un moteur natif dans WSL.
  - Fermer l'app n'arrête pas les agents.
- **Planches** (`--kit`, la référence visuelle) : Marque, Composants, Petite île, Accueil, Agent, Messages, Technique.

## Dernière session (1er octobre)

- L'île et l'accueil suivent la même règle pour ce qui attend : plus d'étoile rouge qui reste.
- La limite de Codex est reconnue (« Limite atteinte », 100 %), et les limites sont en haut de l'accueil.
- Il ne reste que cinq états : travaille, « ! » attend, « ! » rouge erreur, limite, terminé ; rien en pause. Le violet ne sert plus qu'à « Ensorcelé ».
- Menu étoile : une seule étoile visible ; « Supprimer… » ouvre la confirmation sur place.
- Plus de trou blanc dans l'accueil ; l'ombre de l'île n'est plus carrée.

## À valider avec l'utilisateur

- **Dans l'app** : la bulle, la petite île à la fin d'un agent, la confirmation de suppression.
- **Choix en attente** (`design.md` §12) : l'animation de Claude au travail, l'accueil épuré.

## Prochaines étapes, dans l'ordre

1. **Fiabilité en usage réel**, sous Windows et dans WSL : lancer, chat, permissions, questions, pause, arrêt, fermeture puis reconnexion. Vraie reconnexion de session Windows. Claude dans WSL quand le quota le permet.
2. **Performance** : la petite île au repos est passée de 56 à 28 images par seconde (`--bench`). Reste à mesurer l'île ouverte, un long chat et les flous (`--perf`). Peut-être un mode sans animation.
3. **Mémoire de `mikkyd`** : résumés de sessions, détail chargé à la demande.
4. **Relance automatique dans Rust**, si elle doit marcher sans écran (aujourd'hui, fermer l'app la suspend).
5. **R5, nouveaux outils** : OpenCode, pi, OpenClaw, Gemini CLI. Ne garder que ceux qui marchent avec un abonnement sans clé ; vérifier qu'ils parlent ACP.
6. **R6, agents qui se parlent** : lire d'abord la recherche (A2A, MCP, Agora, MAST), puis proposer une spec.
7. **Fonctions suivantes**, à choisir avec l'utilisateur (`idees.md` §7) : routines, boîte de réception, modifier le dernier message, worktrees, pièces jointes, réglages, LocalSend, mails avec Laya, dictée.

Reportés : R4, la grande fenêtre (branche `feature/r4-workspace`) ; R7, le VPS par tunnel SSH.

## Le code

```
daemon/                  Rust : mikky-acp (JSON-RPC ACP), mikkyd (agents, sessions, SQLite, API)
packages/mikky_engine/   Dart pur : Mikky, règles de l'île (IslandMachine), SessionLog, groupes
packages/mikky_agents/   client de mikkyd (DaemonClient, RealAgentSource, AgentStore)
app/lib/island/          l'île (island_view, compact_view = petite île), shader app/shaders/island.frag
app/lib/side/            petite fenêtre : accueil (side_app), agent_page, session_*
app/lib/ui/              composants, pixels (pixel_fx), menu flottant
app/lib/boards/          planches --kit ; images de test dans app/test/goldens/
app/windows/runner/      overlay natif (clics traversants, crochet souris, menus)
```

Mikky écrit dans `%APPDATA%\Mikky\` (réglages, réglage de Mikky). Les adaptateurs sont dans `%LOCALAPPDATA%\Mikky\acp`, et dans WSL dans `~/.local/share/mikky`. Aucun identifiant sur disque.

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
