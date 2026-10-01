# R3 et première fenêtre R4 — 1er octobre 2026

## Architecture livrée

L’app Flutter utilise toujours le backend Rust. L’ancien réglage `daemon` et le chemin `--no-daemon` ont été retirés. `mikky_agents` reste le **client** de l’API et le modèle de présentation, sans lanceur ni lecteur ACP de production. Les anciens lanceurs sont dans `packages/mikky_agents/tool/legacy/`, les lecteurs de référence dans `packages/mikky_engine/test/support/readers/` : uniquement pour les outils de comparaison et les tests.

Rust possède les agents, l’installation des adaptateurs, la connexion aux outils, les lecteurs ACP/Claude/Codex, la surveillance native et SQLite. **Protocole 3** : événements normalisés communs, pages de 256, séquences de reprise, identifiants propres à chaque daemon. Le trafic brut n’est plus dupliqué dans le backlog de production. Les permissions et questions restent dans Rust sans écran connecté. Fermer Flutter détache l’écran ; arrêter tous les agents est une action séparée.

SQLite (WAL, transactions, thread dédié) conserve les métadonnées ; `agents.json` est importé une fois, conservé en original. Les changements sont annoncés à tous les écrans, puis relus en préservant les modifications locales en attente. Une session en cours de création dans un autre écran n’est plus supprimée comme un ancien brouillon. La suppression volontaire d’un fichier de session passe par Rust et n’accepte que les sessions connues du watcher.

WSL possède son daemon natif, séparé du pont Windows : socket privé, répertoire 0700, contrôle de l’UID, processus détaché et groupes de processus pour les agents. Les anciens moteurs ne sont mis à jour automatiquement que si leur inventaire ne contient aucun agent ; une machine distante indisponible ne vaut pas inventaire vide. Le binaire Linux doit être remplacé par renommage atomique : écraser un ELF chargé peut provoquer un crash sous WSL. Le script Linux utilise désormais cette méthode.

## Application utilisable

`Start-Mikky.ps1` ouvre la grande fenêtre `--home` ; `-Island` ouvre l’île, `-Boards` les planches, `-InstallStartup` enregistre aussi le moteur à la connexion Windows. Le menu de l’île ouvre également l’espace de travail. La fenêtre réutilise les vrais écrans de sessions, création, chat et permissions ; sa colonne indique les états Windows/WSL. Fermeture indépendante des fenêtres.

`--kit` contient **Technique** (parcours, séparation, optimisations, mesures et suite) et **Espace** (cadre de la grande fenêtre). Les références claires/sombres sont testées. Les équipes, autres harnais et VPS ne sont pas simulés dans cette première fenêtre : ils restent R5–R7.

`scripts/Build-Windows.ps1` compile les deux backends avec Flutter, vérifie le contenu du bundle et copie un dossier versionné dans `dist/`. Il ne modifie pas la configuration Flutter globale et n’écrase pas les exécutables utilisés par une fenêtre ouverte. `dist/current.txt` désigne le bundle à lancer. Le bundle entier doit être conservé, pas seulement `mikky.exe`.

## Vérifications

- Bundle Windows release lancé le 1 octobre : fenêtre « Mikky - Espace de travail » active, moteur persistant répondant en protocole 3. Tâche Windows `Mikky-mikkyd` enregistrée et prête, pointant sur le bundle versionné `dist/Mikky-20261001-103002`. Aucune fermeture de session Windows effectuée pour ce contrôle.

- 14 tests Rust ; lecteurs de fichiers testés sur toutes les fixtures existantes.
- 56 tests du client Dart ; sept enregistrements ACP comparés message par message au lecteur de référence, permissions et questions comprises dans les tests de processus.
- 111 tests du moteur d’affichage ; 46 tests Flutter, dont service/reconnexion et planches.
- Scénario WSL opt-in : permission conservée après fermeture puis relance du hub Windows, validé après la migration au protocole 3.
- Synchronisation de deux écrans : métadonnées partagées et modifications locales en attente préservées.
- Migration SQLite : import unique, transactions atomiques, relecture après ouverture d’une nouvelle connexion.
- Essai réel précédent : Codex Windows répond « ok » ; Claude WSL atteint l’outil mais rencontre la limite de session de l’abonnement. Ne pas confondre ce blocage avec une validation de réponse complète de Claude.

Pour reproduire : `cargo build`, `cargo build --examples`, `cargo test --workspace` dans `daemon/` ; `dart analyze` / `dart test` dans les deux packages ; `flutter analyze` / `flutter test` dans `app/`. Le test WSL demande `MIKKY_TEST_WSL=1` et `mikkyd-linux` à côté du daemon Windows de test. `backend_smoke.dart` utilise réellement les abonnements ; `backend_perf.dart` ne lance aucun agent.

## Mesure du 30 septembre et limites

Backend Windows release isolé, SQLite en mémoire, sans agent lancé ni WSL : avant lecture par blocs, 24 historiques et 249,5 Mio résidents ; après, 25 historiques et **39,2 Mio résidents / 31,4 Mio privés**. Démarrage+connexion : 208,8 ms ; médiane `hello` : 0,176 ms, p95 : 0,274 ms ; binaire 3,89 Mio. Aucun incrément CPU détecté sur 5 s de repos. Le jeu de sessions a évolué d’une session : ce n’est pas une charge contrôlée, ni une mesure de Flutter ou WSL. La correction supprime la capacité du fichier entier conservée inutilement dans le tampon de lecture.

Les événements normalisés et les historiques récents restent en mémoire ; la pagination réseau ne borne pas leur volume. Des résumés et un chargement du détail à la demande restent une optimisation à faire avec mesures. Le profilage des longues conversations Flutter reste à mener. La relance après quota (« Ensorcelé ») est encore une fonction de l’écran, pas un ordonnanceur Rust durable : fermer cet écran suspend cette automatisation. Le démarrage Windows peut être vérifié par enregistrement/inspection, sans prétendre avoir redémarré la session de l’utilisateur.

Suite : charger les historiques à la demande et poursuivre R4 ; R5 descriptions des harnais ; R6 recherche/spec puis équipes et canal ; R7 VPS par SSH. Ces fonctionnalités ne sont pas annoncées comme livrées.
