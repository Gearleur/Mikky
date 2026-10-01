# Suivi technique — 1er octobre 2026

**Référence actuelle : `main`, île flottante et petite fenêtre.** La grande fenêtre de monitoring est reportée sur `feature/r4-workspace`. Elle ne fait plus partie de l'application livrée sur `main`. La priorité reste de fiabiliser et optimiser l'île.

## Historique des changements

| Référence | Travail | Statut |
| --- | --- | --- |
| `6a9cbee` | Backend Rust persistant, protocole 3, lecteurs, stockage, reconnexion, outils, tests, planche Technique et scripts de livraison ; premier prototype de grande fenêtre | Socle livré ; grande fenêtre retirée ensuite |
| `feature/r4-workspace` | Conservation de la grande fenêtre, de son cadre et de la planche Espace | Branche poussée ; travail reporté |
| `92c6be6` | Retour au lancement de l'île, retrait de HomeApp, de `--home`, du menu et de la planche Espace sur main | Livré et poussé |

La planche **Technique** résume ce suivi avec des couleurs : vert = en place, orange = incomplet, bleu = à mesurer, violet = prévu ou reporté. Ces statuts décrivent le code, pas des contrôles en direct.

## Architecture livrée

L’app Flutter utilise toujours le backend Rust. L’ancien réglage `daemon` et le chemin `--no-daemon` ont été retirés. `mikky_agents` reste le **client** de l’API et le modèle de présentation, sans lanceur ni lecteur ACP de production. Les anciens lanceurs sont dans `packages/mikky_agents/tool/legacy/`, les lecteurs de référence dans `packages/mikky_engine/test/support/readers/` : uniquement pour les outils de comparaison et les tests.

Rust possède les agents, l’installation des adaptateurs, la connexion aux outils, les lecteurs ACP/Claude/Codex, la surveillance native et SQLite. **Protocole 3** : événements normalisés communs, pages de 256, séquences de reprise, identifiants propres à chaque daemon. Le trafic brut n’est plus dupliqué dans le backlog de production. Les permissions et questions restent dans Rust sans écran connecté. Fermer Flutter détache l’écran ; arrêter tous les agents est une action séparée.

SQLite (WAL, transactions, thread dédié) conserve les métadonnées ; `agents.json` est importé une fois, conservé en original. Les changements sont annoncés à tous les écrans, puis relus en préservant les modifications locales en attente. Une session en cours de création dans un autre écran n’est plus supprimée comme un ancien brouillon. La suppression volontaire d’un fichier de session passe par Rust et n’accepte que les sessions connues du watcher.

WSL possède son daemon natif, séparé du pont Windows : socket privé, répertoire 0700, contrôle de l’UID, processus détaché et groupes de processus pour les agents. Les anciens moteurs ne sont mis à jour automatiquement que si leur inventaire ne contient aucun agent ; une machine distante indisponible ne vaut pas inventaire vide. Le binaire Linux doit être remplacé par renommage atomique : écraser un ELF chargé peut provoquer un crash sous WSL. Le script Linux utilise désormais cette méthode.

## Application utilisable

`Start-Mikky.ps1` ouvre l’île flottante ; `-Island` reste un alias, `-Boards` ouvre les planches et `-InstallStartup` enregistre aussi le moteur à la connexion Windows. Sessions, création, chat et permissions restent accessibles dans la petite fenêtre de l’île. Le démarrage automatique enregistré concerne le moteur, pas l’ouverture automatique de l’île.

`--kit` contient six planches : Marque, Composants, Accueil, Agent, Messages et **Technique** (parcours interactif, séparation, optimisations, bilan et suite). Les références claires/sombres sont testées. La planche Espace est conservée uniquement sur la branche R4.

`scripts/Build-Windows.ps1` compile les deux backends avec Flutter, vérifie le contenu du bundle et copie un dossier versionné dans `dist/`. Il ne modifie pas la configuration Flutter globale et n’écrase pas les exécutables utilisés par une fenêtre ouverte. `dist/current.txt` désigne le bundle à lancer. Le bundle entier doit être conservé, pas seulement `mikky.exe`.

## Vérifications

- Bundle Windows release de retour à l'île lancé le 1 octobre : `dist/Mikky-20261001-104300`. La grande fenêtre précédente a été fermée. Moteur persistant vérifié en protocole 3 ; tâche Windows `Mikky-mikkyd` enregistrée vers le bundle. Aucune fermeture de session Windows effectuée pour ce contrôle.

- 14 tests Rust ; lecteurs de fichiers testés sur toutes les fixtures existantes.
- 56 tests du client Dart ; sept enregistrements ACP comparés message par message au lecteur de référence, permissions et questions comprises dans les tests de processus.
- 111 tests du moteur d’affichage ; 44 tests Flutter après retrait des deux références Espace (46 avant), dont service/reconnexion et planches. Analyse Flutter et client Dart sans problème signalé.
- Scénario WSL opt-in : permission conservée après fermeture puis relance du hub Windows, validé après la migration au protocole 3.
- Synchronisation de deux écrans : métadonnées partagées et modifications locales en attente préservées.
- Migration SQLite : import unique, transactions atomiques, relecture après ouverture d’une nouvelle connexion.
- Essai réel précédent : Codex Windows répond « ok » ; Claude WSL atteint l’outil mais rencontre la limite de session de l’abonnement. Ne pas confondre ce blocage avec une validation de réponse complète de Claude.

Pour reproduire : `cargo build`, `cargo build --examples`, `cargo test --workspace` dans `daemon/` ; `dart analyze` / `dart test` dans les deux packages ; `flutter analyze` / `flutter test` dans `app/`. Le test WSL demande `MIKKY_TEST_WSL=1` et `mikkyd-linux` à côté du daemon Windows de test. `backend_smoke.dart` utilise réellement les abonnements ; `backend_perf.dart` ne lance aucun agent.

## Mesure du 30 septembre et limites

Backend Windows release isolé, SQLite en mémoire, sans agent lancé ni WSL : avant lecture par blocs, 24 historiques et 249,5 Mio résidents ; après, 25 historiques et **39,2 Mio résidents / 31,4 Mio privés**. Démarrage+connexion : 208,8 ms ; médiane `hello` : 0,176 ms, p95 : 0,274 ms ; binaire 3,89 Mio. Aucun incrément CPU détecté sur 5 s de repos. Le jeu de sessions a évolué d’une session : ce n’est pas une charge contrôlée, ni une mesure de Flutter ou WSL. La correction supprime la capacité du fichier entier conservée inutilement dans le tampon de lecture.

Les événements normalisés et les historiques récents restent en mémoire ; la pagination réseau ne borne pas leur volume. Des résumés et un chargement du détail à la demande restent une optimisation à faire avec mesures. Le profilage des longues conversations Flutter reste à mener. La relance après quota (« Ensorcelé ») est encore une fonction de l’écran, pas un ordonnanceur Rust durable : fermer cet écran suspend cette automatisation. Le démarrage Windows peut être vérifié par enregistrement/inspection, sans prétendre avoir redémarré la session de l’utilisateur.

## Ce qu'il reste à faire, dans l'ordre

| Priorité | Travail restant | Critère de validation |
| --- | --- | --- |
| 1 — Fiabilité de l'île | Vérifier en usage réel création, chat, permissions, questions, pause/reprise, arrêt, fermeture et reconnexion, sur Windows et WSL | Aucun agent arrêté par la fermeture de l'écran ; état et réponses retrouvés après reconnexion |
| 1 — Connexion Windows | Tester une véritable déconnexion/reconnexion Windows ; l'enregistrement de la tâche est déjà vérifié | Moteur disponible sans lancement manuel ; distinguer démarrage du moteur et de l'île |
| 1 — Claude WSL | Refaire un échange réel quand le quota de l'abonnement le permet | Réponse terminée, pas seulement adaptateur accessible |
| 2 — Mémoire | Résumés de sessions, détail chargé à la demande et stratégie de conservation du flux | Mémoire mesurée et maîtrisée avec de nombreux historiques et de longues sessions ; la pagination seule ne suffit pas |
| 2 — Fluidité | Profiler île au repos/animée, chat long, markdown et flous en release | Relevés CPU, RAM et temps de frame reproductibles avant/après sur une même charge |
| 3 — Relance automatique | Décider puis porter la relance après quota dans Rust si elle doit fonctionner sans écran | Tests d'échéance, annulation et redémarrage ; actuellement fermer l'écran suspend cette automatisation |
| Reporté — R4 | Reprendre la grande fenêtre uniquement lorsqu'elle sera souhaitée | Travail conservé sur `feature/r4-workspace`, sans réintroduction automatique sur main |
| Plus tard — R5 | Descriptions et intégration d'autres harnais | Capacités et compatibilité ACP définies et testées |
| Plus tard — R6 | Recherche/spec des équipes et du canal entre agents | Identités, droits, journal et scénarios validés avant implémentation |
| Plus tard — R7 | Moteur sur VPS via SSH | Authentification, reconnexion et arrêt distant testés |

Les routines, déclencheurs, téléphone et web restent des perspectives après ces étapes, sans engagement de livraison actuel.

## Nettoyage et protections ajoutées

- Retrait des lanceurs et lecteurs Dart de production ; conservation explicite des références pour les tests de parité.
- Suppression du mode de secours local silencieux ; états de connexion visibles et reconnexion automatique.
- Synchronisation des métadonnées entre écrans sans écraser les modifications en attente ; préservation des brouillons encore en création.
- Suppression des transcriptions via le backend, limitée aux fichiers de sessions connus.
- Mise à jour automatique d'un ancien moteur seulement après inventaire vide ; pas d'arrêt d'agents actifs pour mettre à jour.
- Remplacement atomique du binaire Linux pour éviter d'écraser un exécutable chargé ; bundles Windows versionnés pour préserver les exécutables ouverts.
- Outils de maintenance, de mesure et de smoke test : `backend_manage.dart`, `backend_perf.dart`, `backend_smoke.dart`. Ce dernier utilise réellement les abonnements.
- Documentation de reprise et scripts de compilation/lancement ; fichiers générés et captures d'échec exclus du suivi Git.
