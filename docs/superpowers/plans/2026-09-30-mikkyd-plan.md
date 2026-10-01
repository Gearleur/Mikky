# Plan — `mikkyd` (R0 à R7)

Spec : `specs/2026-09-30-mikkyd-design.md` (validée le 2026-09-30). Code : `daemon/` (cargo workspace).

## Avancement

**1er octobre : R3 consolidé et première tranche R4 utilisable.** Le lecteur ACP a rejoint Rust ; aucun chemin de lancement local dans Flutter. Les références Dart sont hors production. Le protocole 3 synchronise événements et métadonnées ; les moteurs inactifs peuvent être mis à jour. Une fenêtre `--home` réutilise les vrais écrans de sessions et affiche les machines Windows/WSL. Scripts de build/lancement et détails de validation : [r3-verification.md](../r3-verification.md). R5–R7 restent à réaliser.

**Mise à jour R2/R3 du 2026-09-30 :** voir [l'état vérifié et les limites restantes](../r3-verification.md). Rust possède maintenant les lancements, le stockage SQLite et les sessions extérieures, avec un daemon natif WSL. Fermer Flutter laisse les agents continuer ; reconnexion incrémentale et arrêt global séparé. Le retrait du chemin local et du lecteur ACP Dart reste à terminer : R3 est en consolidation. Cette mise à jour remplace les descriptions du fonctionnement R1 ci-dessous, conservées comme historique.

### R0 — Préparer ✔ (2026-09-30)

- Rust 1.98.1 installé avec rustup, sous Windows (`%USERPROFILE%\.cargo\bin`) et dans WSL (`~/.cargo/bin`).
- `daemon/` : workspace cargo (édition 2024).
- Essai (sans message envoyé, donc gratuit) : Claude (`claude-agent-acp` 0.84.0) et Codex (`codex-acp` 2.0.0) ouverts depuis Rust, **sous Windows et dans WSL** (binaire Linux) : `initialize`, `session/new`, modes, commandes « / ». L'essai passait par le SDK officiel ACP (`agent-client-protocol`) ; **abandonné en R1**, voir plus bas.

### R1 — `mikkyd` fait tourner les agents, sur le PC ✔ (2026-09-30, à voir dans l'app avec l'utilisateur)

**Ce que fait `mikkyd` maintenant** :
- Il lance l'adaptateur (Windows, ou WSL par `wsl.exe -d Ubuntu --cd … -- bash -lc`), sans fenêtre de console, dans un **job object** (tué avec lui).
- Il parle ACP avec l'agent : `initialize`, `session/new` / `session/load`, mode, message, arrêt du tour. Il **garde les demandes de permission et les questions** jusqu'à la réponse d'un écran (Oui / Non / Toujours, choix), et répond « cancelled » à tout ce qui attend quand on arrête le tour.
- Il **renvoie aux écrans chaque message ACP brut**, dans les deux sens et horodaté (`run.traffic`), le passé d'abord. L'app le lit avec son `AcpReader` et son `SessionLog`, déjà testés sur de vrais enregistrements : aucun lecteur réécrit pour l'instant.
- API : JSON-RPC sur WebSocket, `127.0.0.1` seulement, port libre, jeton de 256 bits. Port et jeton sont dans le **coffre de Windows** (identifiant générique `Mikky/mikkyd`, pour la session Windows). Une seule instance par session (mutex `Local\MikkyDaemon`). Toute connexion avec un en-tête `Origin` est refusée (aucune page web ne peut piloter les agents).
- Il **s'arrête seul une minute après le départ du dernier écran**, en arrêtant ses agents. C'est le comportement d'aujourd'hui (les agents s'arrêtent avec l'app), mais un redémarrage rapide de l'app, ou un plantage, ne les tue plus : l'app les reprend (`runs.list`, puis `RealAgentSource.adopt`).
- `mikkyd --stdout-endpoint` : écrit port et jeton sur sa sortie, ne touche pas au coffre, s'arrête quand son entrée se ferme (tests).
- Mesures : binaire release 1,5 Mo, ~10 Mo de mémoire.

**Côté app** :
- `AgentRun` est devenu une interface. `LocalAgentRun` est l'ancien code (l'app parle elle-même à l'adaptateur) ; `DaemonAgentRun` passe par `mikkyd`. `DaemonClient` lit le coffre, démarre `mikkyd` s'il ne répond pas, et parle JSON-RPC.
- `AgentsService` se connecte à `mikkyd` au démarrage et lance les agents par lui. **Retour à l'ancien chemin** : `"daemon": false` dans `%APPDATA%\Mikky\settings.json`, ou `mikky.exe --no-daemon`. Il y revient aussi tout seul si `mikkyd.exe` est introuvable ou ne répond pas.
- `mikkyd.exe` est cherché dans `MIKKYD`, à côté de `mikky.exe`, puis dans `daemon/target/{release,debug}/` en remontant les dossiers (dev).

**Changements par rapport à la spec** :
- **Pas de SDK ACP** : `mikkyd` doit voir et renvoyer chaque message tel quel. Un petit client JSON-RPC maison (`mikky-acp`, comme `AcpConnection` en Dart) le permet, et il gère `elicitation/create`, hors du protocole stable.
- **Reste dans l'app jusqu'à R3** : l'installation des adaptateurs et du Node privé, la connexion des outils, `agents.json` (pas encore SQLite), la surveillance des sessions extérieures (R2). L'app dit à `mikkyd` quoi lancer (exécutable, arguments, dossier, variables).
- Deux crates pour l'instant : `mikky-acp` (connexion + session d'agent) et `mikkyd` (lancement, job, coffre, API). Les autres viendront quand il le faudra.

**Tests** :
- Rust : 10 (`cargo test` dans `daemon/`).
- Dart : `test/daemon_run_test.dart` fait tourner le vrai `mikkyd` avec le faux agent (processus réel) : ouvrir, permissions, question, annuler, agent qui meurt, jeton refusé, un 2e écran qui reprend l'agent avec tout son fil. Il demande `cargo build` d'abord. Paquet : 42 tests, stables sur 4 passes.
- Vrai essai : `dart run tool/smoke.dart --daemon <dossier Windows> <dossier WSL>` (deux tout petits messages). Codex (Windows) et Claude (WSL) répondent « ok » à travers `mikkyd`.

**Point à surveiller** : aux deux premiers essais, Claude dans WSL a échoué par `mikkyd` avec « Failed to refresh OAuth token: another Claude Code process is refreshing it or exited mid-refresh ». Sans `mikkyd`, puis de nouveau par `mikkyd`, ça a marché. C'était sans doute un verrou de renouvellement laissé par un Claude arrêté net, peut-être la sonde R0. Si ça revient, regarder comment Claude verrouille son renouvellement dans WSL.

**Reste pour finir R1** :
- Le voir dans l'app avec l'utilisateur : lancer un agent, Oui / Non, question, arrêter, quitter et relancer l'app.
- Copier `mikkyd.exe` à côté de `mikky.exe` dans le build release (CMake).

### R2 — Sessions extérieures en Rust, `mikkyd` dans WSL

À faire (spec §10).

### R3 à R7

Voir la spec, §10. R3 reprend aussi ce qui est resté dans l'app en R1 (installation, connexion des outils, stockage).

## Notes

- Git Bash ne voit `cargo` qu'après redémarrage du terminal : sinon `export PATH="$HOME/.cargo/bin:$PATH"`.
- Dans WSL, compiler avec `CARGO_TARGET_DIR=$HOME/.cache/mikky-daemon-target` (bien plus rapide que sur `/mnt/c`), et mettre le Node privé dans le PATH (`~/.local/share/mikky/node/bin`).
- Ouvrir une session sans message ne laisse pas de session dans Claude ni dans Codex ; Claude crée juste un dossier de projet vide dans `~/.claude/projects/`.
- **Ordre des messages** : `mikkyd` enregistre chaque message au moment où il le lit ou l'écrit (un « hook » synchrone), avant que la requête qu'il termine ne se résolve. Sinon, la réponse à `run.prompt` arrive à l'app avant les derniers mots de l'agent, et un Oui peut partir avant que `mikkyd` connaisse la demande.
- **Dart** : un `StreamController.broadcast()` asynchrone livre **un événement par micro-tâche**. Une réponse qui suit une rafale de notifications passe donc devant elles. `DaemonClient` utilise `sync: true`.
- **Rust** : `m.lock().unwrap().a + m.lock().unwrap().b` bloque pour toujours (le premier verrou vit jusqu'à la fin de l'expression).
