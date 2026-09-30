# Mikky — où on en est (pour reprendre)

Dernière mise à jour : 2026-09-30 (fin de session) · Dépôt : https://github.com/Gearleur/Mikky (branche `main`)

À lire en premier dans une nouvelle conversation, avec `CLAUDE.md` et `idees.md` (toutes les idées et le MVP choisi). Spec et plan de l'étape 1 : `specs/2026-09-28-etape-1-design.md`, `plans/2026-09-28-etape-1-plan.md`.

## 0. En bref

- **L'étape 1 marche** : Mikky et son île sous Windows (§1).
- **Depuis le 2026-09-29, Mikky est un compagnon d'agents** : il lance et suit Claude Code et Codex, un « Paperclip plus simple » (`idees.md`). Spec du MVP validée : `specs/2026-09-29-mvp-design.md`. Plan et avancement détaillé : `plans/2026-09-29-mvp-plan.md` (A0 à A7).
- **Fait (A0 à A7.6)** :
  - Claude et Codex lancés et suivis par ACP, sous Windows ou dans WSL (les quatre combinaisons vérifiées depuis la fenêtre), Demander / Auto, Oui / Non / « Toujours », questions à choix de Claude (vérifié avec le vrai Claude), arrêt d'un agent (job object), continuer un agent, reprise après redémarrage, sessions lancées ailleurs (VS Code, terminal) vues en direct.
  - La petite fenêtre à droite (`app/lib/side/`) : accueil en groupes, page d'un agent (Suivi / Chat), nouvel agent (dossier, modèle, Où, Permissions), connexion. Clic en dehors qui referme, copier / coller, Mikky qui prend l'état de l'agent.
  - Ranger les sessions : renommer, épingler, archiver, erreur réglée, supprimer (avec ou sans le fichier, confirmé), reprises reliées à l'originale, erreurs qui traînent sorties d'« En attente ».
  - Logos des outils (Lobe icons via Paperclip, MIT) ; icône Mikky (app + zone de notification) ; notifications Windows (attend, question, erreur, fini ; réglable dans le menu).
  - Contexte et jetons d'un agent ; limites de l'abonnement Codex (5 h, semaine) sur l'accueil.
  - Chat : blocs de code avec « Copier », liens cliquables, gras, listes ; « Ouvrir dans VS Code » / « Ouvrir le dossier » ; commandes « / » de l'agent au-dessus du champ.
- **Pas encore vu à l'écran** (à vérifier avec l'utilisateur) : l'icône de la zone de notification et les notifications ; les commandes « / » avec le vrai Claude ; « Ouvrir dans VS Code » en WSL.
- **Pas encore poussé sur GitHub** : les commits depuis A7.1 (demander avant de pousser).
- **Décisions** : ACP comme Paperclip ; abonnements seulement, pas d'API ; Mikky n'est pas un harnais ; pas de Haiku ; Node privé de Mikky dans WSL ; agents dans un job object Windows ; sélecteurs un peu plus gluants (ressort 380 / 0,70) ; barre d'onglets gardée pour plus tard. Ne jamais piloter souris / clavier (SendInput) pendant que l'utilisateur utilise le PC.

### Prochaine session, dans l'ordre (demandé par l'utilisateur le 2026-09-30)

1. **Essayer les nouveaux outils** : OpenCode, pi, OpenClaw, Gemini CLI. Aucun n'est installé (ni Windows ni WSL). Pour chacun : l'installer, voir comment il se connecte **avec un abonnement, sans clé d'API** (sinon on le laisse de côté), s'il parle ACP (Gemini CLI a un mode ACP, `--experimental-acp` ; OpenCode aurait `opencode acp` ; pi et OpenClaw : à vérifier), puis le brancher comme Claude et Codex (`AgentProvider`, `AgentSetup`, lecteur de ses fichiers de session). Logos déjà prêts (`app/lib/ui/brand_logo.dart`).
2. **Les agents se parlent et se donnent des tâches** (A7.7), même sans mémoire commune : **d'abord lire la recherche**, puis proposer une spec à l'utilisateur. Questions : messagerie en langage naturel, JSON structuré, ou un mélange (enveloppe structurée + texte libre) ? Comment déléguer une tâche et récupérer le résultat ? Pistes à vérifier (ne rien citer sans l'avoir lu) : protocole A2A de Google (tâches, « agent cards »), MCP (un serveur MCP de Mikky donné à chaque agent, façon VelaTerm `vsearch` / `vrefer` / `vtell`), Agora (méta-protocole : langage naturel puis protocoles structurés négociés), « Why Do Multi-Agent LLM Systems Fail? » (MAST, 2025 : échecs de coordination), les revues de protocoles de communication entre agents (2025), la communication par état latent / cache KV (impossible entre Claude et Codex fermés, à noter seulement), ce que font Paperclip, Claude Code (sous-agents, équipes d'agents) et Codex.
3. **Choisir les fonctions les plus importantes** pour la suite, avec l'utilisateur (liste complète : `idees.md` §7, items 41 à 67). Ma proposition : tâches planifiées / routines (55, partie B du MVP), boîte de réception de tout ce qui attend (47), modifier / renvoyer le dernier message (62), worktrees par lancement (58), pièces jointes (59), écran de réglages (67), puis LocalSend, mails avec Laya, dictée.
4. En passant : finition A6 (menus natifs → menus aux couleurs des maquettes, mesures).

## 1. Ce qui marche (étape 1, sous Windows)

- **Overlay** : fenêtre transparente, toujours au premier plan, absente de la barre des tâches, clics traversants sauf sur l'île, hook souris global (`WH_MOUSE_LL`, 60 Hz max), 0 % de CPU île cachée. Code natif dans `app/windows/runner/flutter_window.cpp` (canal `mikky/overlay` : `setHitRect`, `setPlacement`, `showMenu`, `activate`, `quit`).
- **Île** : shader SDF (`app/shaders/island.frag`), thèmes noir « A » et blanc « pur », deux positions (en haut ; à droite en format téléphone), bulle séparée, trait de compte à rebours, contenu Focus.
- **Cerveau de l'île** : `IslandMachine` (règles 1 à 10 de la spec, sans timer, réveillée à `nextDeadline`) + `DemoAgentSource` (faux agents), lancé au démarrage. `AgentSource` est l'interface prévue pour les vrais agents.
- **Mikky** : 11 états, 7 émotes, particules, badges, interactions, et ses **transformations** (§6). Il prend l'état de l'agent en focus.
- **Menu** (clic droit sur l'île) : thème, position, Démo, Réglage de Mikky…, Quitter. Choix gardés dans `%APPDATA%\Mikky\settings.json`.
- **Écran de réglage** : `mikky.exe --tuning`, curseurs enregistrés dans `%APPDATA%\Mikky\tuning.json`.
- **Tests** : 75 dans `packages/mikky_engine` ; goldens dans `app/test/goldens/`.

Reste de l'étape 1, pas urgent : valider les expressions sans transformation (question, erreur, limité, cherche, dort, sonné) ; figer les proportions dans `MikkyTuning` ; goutte de notification et points vivants (J3) ; icône et menu de la zone de notification (J5) ; masquer l'écran de réglage hors build de dev.

## 2. Le MVP choisi (détails dans `idees.md` §1)

1. Lancer **Claude Code et Codex** depuis la petite fenêtre à droite, et **voir qui travaille** — tout le monde, y compris les sessions lancées dans VS Code ou le terminal (Claude écrit ses sessions dans `~/.claude/projects/`, Codex dans `~/.codex/sessions/AAAA/MM/JJ/` : il suffit de surveiller ces fichiers, sans boucle).
2. **LocalSend** dans Mikky.
3. **Classer les mails Gmail en local** avec **Laya** (https://huggingface.co/convaiinnovations/laya, version multilingue ~322 M, Apache 2.0, Python `pip install laya`). Proposé : lecture seule par IMAP avec un mot de passe d'application gardé dans le coffre de Windows.
4. **Parler au lieu d'écrire** : micro dans le champ ou raccourci **Ctrl + Win maintenus** (validé). La dictée par **Whisper en local** est validée mais **pour plus tard**.

Ensuite, dans l'ordre voulu par l'utilisateur : gérer Claude et Codex, **planifier des tâches**, puis les apps tierces (mini-apps, communauté, plugins).

## 3. Design validé (maquettes HTML, la référence visuelle)

- **UI** : `design/prototypes/composants.html` — boutons, sélecteurs, interrupteurs, champs, navigation, états d'un agent, notifications, et le tableau des animations (valeurs à reprendre dans Flutter). Couleurs et formes tirées de `design/references/boutons-lanceur.png` (gris, blanc, noir ; capsules, boutons ronds ; **pas** la mise en page « lecteur »). Style commun : `design/prototypes/mikky-ui.css` (jetons clair / sombre). Quelques petits bugs à corriger plus tard.
- **UX** : `design/prototypes/ux-a.html` (piste A, en simple) :
  - **Accueil** : les agents en groupes repliables **En attente / Travaillent / Terminés / Historique** ; un bouton rond noir avec une flèche → vers la droite, en bas à droite, qui ouvre le chat d'un **nouvel agent**. Pas de résumé, pas de barre horizontale.
  - **Page d'un agent au travail** : deux vues, **Suivi** (la ligne de métro de ses tâches, trait bleu qui avance avec un halo très léger et lent, code en direct sous l'étape en cours, messages glissés entre les tâches) et **Chat** (l'historique complet, chat normal). **Quand la tâche est finie**, retour au chat normal, la tâche devient une carte « Tâche terminée » qui se déplie.
  - **Le champ de saisie** : style « Champ » des composants (gris en creux), micro + flèche d'envoi à droite, grandit jusqu'à 5 lignes ; options **à moitié dans le champ** en bas à gauche : dossier + modèle (nouvel agent) ou Suivi | Chat (agent au travail).
- Mikky en petit en haut à gauche de l'accueil (images `design/references/mikky-idle-{light,dark}.png`, rendues par le vrai painter).
- Captures des maquettes : Chrome headless avec `#calme` dans l'URL (animations figées) ; `#sombre` pour le thème sombre ; `#grand` pour des fenêtres plus hautes.

## 4. Comment le code est rangé (partie A du MVP)

```
packages/mikky_engine/    Dart pur : Mikky, l'île (IslandMachine), agents (AgentSource),
                          sessions (lib/src/sessions : SessionEvent, lecteurs ACP / Claude / Codex,
                          SessionLog = fil + tours + plan + état, groupes de l'accueil)
packages/mikky_agents/    Dart + dart:io : Target (Windows / WSL), job.dart (job object),
                          acp/ (AcpConnection, AgentRun), setup.dart (dossier de Mikky, adaptateurs,
                          Node privé WSL), auth.dart (connexion), watch/ (SessionWatcher),
                          store.dart (agents.json), real_source.dart (RealAgentSource)
app/lib/agents/           AgentsService : les vrais agents dans l'app
app/lib/ui/               les composants (A3) et l'écran --kit ; markdown.dart (réponses des
                          agents), brand_logo.dart (logos), selection.dart (copier)
app/lib/side/             la petite fenêtre (A4) : side_app (navigation + accueil), agent_page,
                          new_agent_page (+ connexion), session_views (Suivi / Chat, cartes
                          Oui / Non et questions), session_menu (ranger, ouvrir, renommer)
app/lib/island/           l'île ; à droite et ouverte, elle affiche la petite fenêtre
app/windows/runner/       overlay natif : clics traversants, crochet souris (curseur et clic
                          en dehors), menu natif, sélecteur de dossier, activation du clavier
```

Où Mikky écrit : `%APPDATA%\Mikky\` (`settings.json`, `tuning.json`, `agents.json`) ; adaptateurs dans `%LOCALAPPDATA%\Mikky\acp` et, dans WSL, `~/.local/share/mikky` (Node privé, adaptateurs, sonde `watch.mjs`). Aucun identifiant.

Pas encore de `mikkyd` : l'app lance Claude et Codex elle-même, et ils s'arrêtent avec elle. `mikkyd` viendra avec le VPS et le téléphone.

## 5. Brancher Claude et Codex (comme Paperclip, par ACP)

Tout est dans la spec du MVP (§3) et dans le résultat d'A0 (plan). L'essentiel :
- Mikky lance les adaptateurs officiels `claude-agent-acp` et `codex-acp` (comme Paperclip, MIT) et leur parle en ACP ; ils font tourner le vrai Claude Code et le vrai Codex, sur le compte de l'utilisateur. Mikky ne touche jamais aux jetons.
- Permissions choisies à chaque lancement : **Demander** (Claude `default`, Codex `read-only`) ou **Auto** (Claude `auto`, Codex `agent`). Avec Codex, « Non » arrête le tour.
- Cible par lancement, déduite du dossier : Windows, ou WSL (`wsl.exe`, chemin Linux donné à la session). Sur ce PC, Claude et Codex sont installés et connectés des deux côtés.
- Sessions lancées ailleurs : fichiers de Claude (`~/.claude/projects`) et de Codex (`~/.codex/sessions`) surveillés, des deux côtés (dans WSL par une petite sonde, Windows ne voyant pas les changements de WSL).
- App sous Linux (plus tard) : seul l'overlay natif (`app/windows/runner/`) est à refaire.

## 6. Direction artistique de Mikky (validée, ne pas revenir dessus)

Les transformations : **c'est Mikky lui-même qui se transforme**, de façon organique et imparfaite, en gardant sa couleur, ses poils, et **le plus possible sa forme de base**. Tentatives rejetées : un vrai cœur (« trop cœur »), des boules bosselées, des piques, des brins fins, des touffes épaisses, trois boules pour « ••• ».

| Quoi | Ce qui a été validé |
|---|---|
| Amour | la mascotte **à peine** déformée en cœur (oreilles arrondies en lobes, bas en pointe douce), yeux contents, petits cœurs au-dessus des oreilles |
| Travaille | boule de poils = **la mascotte sans oreilles**, ses poils de base ressortant un peu plus tout autour ; pas de secousse ; redevient le chat de temps en temps (boule 6-9 s, chat 2,5-4 s) |
| Réfléchit | la même boule de poils, qui sautille ; redevient le chat de temps en temps (4-6 s / 2-3 s) |
| Attend ton feu vert | en boucle : 2 sauts en chat → « ! » sans yeux (barre large en haut, fine en bas, point bien séparé) pour 3-4 sauts → chat… ; pas de badge |
| Terminé | pas de roulade : petit saut un peu plus haut, yeux contents, une oreille plus grande, étincelles |
| Surpris | grands yeux ronds, oreilles très hautes |

Changement d'une forme à l'autre : mou comme de la gelée (ressort 95 / 0,38), toujours en repassant par le chat. Code : `packages/mikky_engine/lib/src/mikky/` (`mikky.dart`, `mikky_geometry.dart`).

## 7. Lancer, tester, vérifier

- App : `C:\dev\flutter\bin\flutter.bat run -d windows` dans `app/`, ou `app\build\windows\x64\runner\Release\mikky.exe` après `flutter.bat build windows --release`. Écran de réglage : ajouter `--tuning`.
- Moteur : `C:\dev\flutter\bin\dart.bat test` dans `packages/mikky_engine`.
- Goldens : `C:\dev\flutter\bin\flutter.bat test --update-goldens test/mikky_expressions_test.dart` dans `app/`, puis **regarder les images**.
- Vérif à l'écran : captures GDI avec `CAPTUREBLT`, souris simulée avec `SendInput` (pas `SetCursorPos`), prototypes rendus avec Chrome headless (voir `CLAUDE.md`).
- Composants : `mikky.exe --kit` (`--perf` pour les temps d'image). Essai des vrais agents sans l'app : `dart run tool/smoke.dart <dossier Windows> <dossier WSL>` dans `packages/mikky_agents` (deux tout petits messages).
- Essais à l'écran de la petite fenêtre : souris simulée par `SendInput` (structure `INPUT` de 40 octets en x64 !), clavier par `SendKeys`, capture avec `CAPTUREBLT`.

## 8. Pièges déjà rencontrés

- **`late final` + initialiseur qui démarre quelque chose** (ticker, canal) : jamais créé si personne ne le lit. Créer dans `initState`.
- **Chaînes C++ avec accents** : le compilateur lit mal l'UTF-8 ; écrire `\u00e9`. L'outil d'édition convertit `\u2060` / `\u00e9` en vrai caractère : passer par un petit script si besoin.
- **PowerShell** met une virgule décimale dans les noms de fichiers (`burst-10,4.png`).
- **Contour de Mikky** : les courbes en cloche sur l'angle doivent « faire le tour » (`_bell`), sinon marche à la jointure.
- La fenêtre de réglage lancée depuis un terminal s'ouvre derrière les autres fenêtres (normal).
- L'utilisateur utilise le PC pendant les tests : ses mouvements de souris peuvent fausser les tests automatiques.
- **Maquettes HTML** : les captures Chrome headless ne laissent pas finir les animations Web (WAAPI) ; utiliser `#calme`. Une apostrophe droite dans une chaîne JS entre guillemets simples casse toute la page : vérifier avec `node --check` sur le script extrait. Pour les gros remplacements, écrire un script Python dans un fichier plutôt qu'un heredoc dans le shell.
- **Git Bash convertit les chemins** passés à un programme Windows (`/tmp/x` devient `C:/Program Files/Git/tmp/x`) : préfixer `MSYS_NO_PATHCONV=1` quand on passe des chemins Linux à `dart.bat` ou `wsl.exe`.
- **`wsl.exe` écrit ses erreurs en UTF-16** : décoder la sortie avec `Utf8Decoder(allowMalformed: true)`, sinon Dart plante.
- **Dans WSL, lancer avec `bash -l`** : sans shell de connexion, `codex` et `claude` peuvent être ceux de Windows (le PATH de Windows est ajouté à la fin).
- `pkill -f "codex login"` tue aussi le shell qui le lance (son texte contient le motif) : passer par un script.
- **Les retours à la ligne ne passent pas la ligne de commande de Windows** vers `wsl.exe` : un script de plusieurs lignes va sur l'entrée de `bash -s` (`Target.run(input:)`).
- WSL vide `/tmp` quand il redémarre : ne pas y laisser ce qui doit durer.
- Flux Dart `broadcast(sync: true)` : un écouteur qui répond tout de suite (ou un `await` sur `firstWhere`) repasse dans le flux en cours d'envoi. Les flux lus par l'app ou les tests (`changes`, `updates`) sont asynchrones.
- Chaînes Dart : `$HOME` dans une chaîne est une interpolation, écrire `\$HOME`.
- **Exporter Mikky en PNG transparent** : un test Flutter temporaire avec `matchesGoldenFile('../../design/references/…')` et `--update-goldens`, puis supprimer le test.

- **`future.whenComplete(() => map.remove(k))`** quand la map contient ce même futur : la flèche renvoie le futur, que `whenComplete` attend… lui-même, pour toujours. Écrire un bloc `{ map.remove(k); }`.
- **Agent dans WSL** : la session ACP doit recevoir le chemin Linux (`/tmp/x`), pas `\\wsl.localhost\…` ; sinon Codex part de `/tmp` et ses commandes échouent (`AgentRun.workingDirectory`).
- **Scripts Python avec des antislashs** (chemins Windows) dans un heredoc : `\U`, `\x`… cassent la chaîne. Écrire le script dans un fichier, avec des chaînes `r'...'`, ou passer par l'outil d'édition.
- Un `Stack` dont les enfants ne sont pas positionnés les laisse à leur taille : les pages de la petite fenêtre ont besoin de `StackFit.expand`.

## 9. Mesures (release, 1920 × 1080 à 100 %, 12 cœurs)

Île cachée : 0 % · île ouverte animée : ~1 % du CPU total · mémoire : ~60 Mo (Gestionnaire des tâches).
