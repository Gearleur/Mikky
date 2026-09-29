# Mikky — où on en est (pour reprendre)

Dernière mise à jour : 2026-09-29 (fin de session) · Dépôt : https://github.com/Gearleur/Mikky (branche `main`)

À lire en premier dans une nouvelle conversation, avec `CLAUDE.md` et `idees.md` (toutes les idées et le MVP choisi). Spec et plan de l'étape 1 : `specs/2026-09-28-etape-1-design.md`, `plans/2026-09-28-etape-1-plan.md`.

## 0. En bref

- **L'étape 1 marche** : Mikky et son île sous Windows, avec de faux agents (§1).
- **Le 2026-09-29, le projet a grandi** : Mikky devient un compagnon qui suit et pilote nos agents Claude Code et Codex, un « Paperclip plus simple », à terme un mini-téléphone avec des mini-apps. Tout est noté et numéroté dans `idees.md`.
- **L'UI et l'UX de la petite fenêtre (position « à droite ») sont validées** sur maquettes HTML (§3). L'utilisateur a dit : « tout est pas mal, on peut avancer ».
- **Prochaine étape : commencer l'app** (§4), en commençant par brancher Claude (abonnement) et Codex comme le fait Paperclip (§5).
- **Fait le 2026-09-29 (après-midi)** : spec du MVP validée (`specs/2026-09-29-mvp-design.md` : Claude et Codex par ACP comme Paperclip, pas d'API, pas un harnais), plan de la partie A (`plans/2026-09-29-mvp-plan.md`), **A0** (essai ACP réussi sous Windows et dans WSL, résultats dans le plan) et **A1** (moteur des sessions, 100 tests). Claude installé sous Windows ; Codex connecté dans WSL ; Node privé de Mikky dans WSL. **A2** fait aussi (`packages/mikky_agents`, 28 tests, essai en vrai réussi). Pas de Haiku dans les modèles proposés (décision). **Suite : A3** (composants en Flutter).

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

## 4. Prochaine session : commencer l'app

Proposé (à valider avec l'utilisateur au début du chat) :

1. Écrire la **spec du MVP** (`docs/superpowers/specs/`) à partir de `idees.md` et des maquettes, puis le plan.
2. **Brancher Claude et Codex** en reprenant l'approche de Paperclip (§5) : une `AgentSource` réelle derrière l'interface existante.
3. Porter la **petite fenêtre** (accueil, page d'un agent, champ) en Flutter avec les composants validés.
4. Puis : planifier des tâches ; LocalSend ; mails ; dictée.

Décision prise pour le MVP (proposée, non contestée) : **pas encore de `mikkyd`** (le démon Rust) ; l'app lance Claude et Codex elle-même. `mikkyd` viendra avec le VPS et le téléphone.

## 5. Brancher Claude et Codex comme Paperclip

Paperclip est sous licence **MIT** : on peut reprendre ses idées et du code (en gardant la mention de licence). Ses adaptateurs : `packages/adapters/claude-local/` et `packages/adapters/codex-local/` sur https://github.com/paperclipai/paperclip.

- **Claude** (`claude-local/src/server/execute.ts`) : lance le `claude` officiel avec `--print --output-format stream-json --verbose`, et `--resume <id>` pour reprendre une session. Mode **abonnement** si `ANTHROPIC_API_KEY` n'est pas défini (l'utilisateur est connecté lui-même dans `claude`) ; sinon mode API. Autres fichiers utiles : `parse.ts` (lecture du flux), `auth-check.ts`, `quota.ts` / `quota-probe.ts` (limites), `permissions.ts`, `setup-token-runner.ts`.
- **Codex** (`codex-local/src/server/codex-args.ts`, `execute.ts`) : `codex exec --json`, sandbox `workspace-write` par défaut (`-c sandbox_mode="workspace-write"`), `resume <id> -` pour reprendre. Connexion par le compte ChatGPT : voir `codex-home.ts`, `auth-check.ts`, `device-login-runner.ts`, `CODEX-AUTH-CACHE.md`.
- **Permissions (décision du 2026-09-29)** : Paperclip saute les permissions par défaut ; Mikky, lui, propose **un choix par lancement** : **Demander** (par défaut : chaque demande arrive dans Mikky, Oui / Non, via les hooks de Claude Code ou `--permission-prompt-tool`) ou **Auto** (le mode de permission automatique de Claude, et l'équivalent Codex : `approval_policy` / sandbox), que l'utilisateur choisit lui-même.
- **Où tournent les agents (décision du 2026-09-29)** : l'utilisateur veut pouvoir lancer Claude et Codex **sous Windows ou dans WSL**, au choix, et que **l'app marche aussi sous Linux**. Donc une cible par lancement : Windows natif, WSL (`wsl.exe -d Ubuntu -- claude …`), plus tard Linux natif. Sur ce PC :
  - **WSL (Ubuntu)** : `claude` 2.1.284 (`/home/gearleur/.local/bin/claude`) et `codex` installés ; sessions dans `/home/gearleur/.claude/projects` et `/home/gearleur/.codex/sessions` (vues de Windows par `\\wsl.localhost\Ubuntu\home\gearleur\…`).
  - **Windows** : `codex` 0.153.4 (npm) ; `claude` pas dans le PATH (seulement celui de l'extension VS Code), à installer si on veut Claude côté Windows.
  - Pour « voir qui travaille », surveiller les sessions des deux côtés.
  - App sous Linux : Flutter le permet, mais l'overlay natif (`app/windows/runner/`) est à refaire pour Linux (X11 / Wayland : fenêtre toujours au premier plan et clics traversants plus difficiles sous Wayland).
- Mikky ne touche jamais aux jetons : il lance les CLI officiels sur lesquels l'utilisateur s'est connecté.

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

## 9. Mesures (release, 1920 × 1080 à 100 %, 12 cœurs)

Île cachée : 0 % · île ouverte animée : ~1 % du CPU total · mémoire : ~60 Mo (Gestionnaire des tâches).
