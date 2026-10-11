# Feuille de route du 2026-10-08

Écrite après une nouvelle comparaison avec Coucou (`~/projects/coucou`, version 0.2.1 du 7 octobre) et les retours de l'utilisateur du même jour. Elle remplace la liste « Prochaines étapes » de `reprise.md` pour les semaines qui viennent. La vision long terme (le « Discord » agentique et le « Jira nouvelle génération ») est dans `idees.md` §10.

## Où on en est face à Coucou

**Ce que Mikky a en plus** : `mikkyd` lance et pilote les agents (ACP, Windows et WSL, ils survivent à la fermeture de l'app), « Ensorcelé », les outils du mouvement. Coucou ne fait que regarder par les hooks. C'est la fondation du futur « Discord ».

**Ce qui manque**, et ce qu'on en fait :

| Manque | Décision du 2026-10-08 |
|---|---|
| Hooks installés chez l'utilisateur | **Pas installés** (vérifié : `~/.claude/settings.json` n'a pas de `hooks`, le relais n'est pas dans `%LOCALAPPDATA%\Mikky\bin`). À installer depuis le menu une fois les questions branchées. |
| Questions de Claude par les hooks | **À faire** : `mikkyd` les laisse aujourd'hui au terminal. Elles doivent arriver dans le notch et se répondre facilement. |
| Ce qui attend l'utilisateur | **Le notch s'ouvre directement sur la demande la plus prioritaire**, pas sur l'accueil ; on enchaîne au clavier. |
| Vue du diff | **À faire** : un clic sur `+N −M` ouvre le diff. |
| Limites de Claude | L'arrêt sur limite marche déjà (message de fin lu). Les pourcentages 5 h / semaine (comme Codex) : plus tard, par la `statusLine`. |
| Sauter à l'application ou au terminal | **Ctrl + clic sur un agent** (tuile, tâche que Mikky regarde, ligne, carte de demande). |
| Glisser un fichier sur l'île | **Mikky l'avale comme Kirby** : une bouche s'ouvre, il gonfle, avale, puis demande « à quel agent ? ». Exception voulue par l'utilisateur à la règle « pas de bouche » : seulement le temps d'avaler. |
| GitHub | Plus tard (« on verra ») ; il servira le « Discord » (issues → tâches, PR, CI). |
| Plus d'agents (OpenCode, Gemini CLI…) | R5, après. |
| Chat par API, Mikky sur le bureau, récap de la semaine, installateur | Après. |

## Le chantier en cours : trois sous-agents en parallèle

Chacun travaille dans son propre worktree, commit sur sa branche ; on fusionne ensuite dans `main`. Contrat commun posé avant de commencer : `AgentsService.reveal(sessionId)` (`app/lib/agents/agents_service.dart`), qui renvoie `false` tant que le back ne l'a pas fait.

### 1. Back : hooks, questions, sauter à l'application

Propriétaire de : `daemon/`, `packages/mikky_agents/`, la partie données de `packages/mikky_engine/lib/src/sessions/`, `app/lib/agents/`, un nouveau fichier natif pour la fenêtre à mettre devant (`app/windows/runner/`).

1. ✅ (8 oct., branche back) **Questions de Claude par les hooks** : Claude Code (2.1.85 et plus) envoie `AskUserQuestion` en `PreToolUse` ; un hook avec `matcher: "AskUserQuestion"`, `mikky-hook --ask` attend la réponse et renvoie `permissionDecision: "allow"` avec `updatedInput` (questions + réponses). Réponse en terminal ou pas de réponse : aucune sortie, Claude repose la question. Vérifier la doc officielle (https://code.claude.com/docs/en/hooks) et le format multi-choix. Codex : voir s'il a l'équivalent. *(Vérifié : multi-choix = tableau de libellés, clé = texte de la question. Codex n'a pas d'équivalent : ses hooks ne posent pas de question.)*
2. ✅ `hooks.answer` accepte des réponses ; la question d'un hook arrive dans l'app comme les questions ACP (`Question`, `QuestionAsked`), pour que la même carte serve aux deux. *(`RealAgentSource.questionOf` / `canAnswerQuestion` / `answerQuestion`.)*
3. ✅ **Sauter à l'application** : le relais transmet d'où vient la session (processus parent, `TERM_PROGRAM`, `WT_SESSION`, `VSCODE_PID`, `cwd`) ; `mikkyd` le garde avec la session. `reveal(sessionId)` : met devant la fenêtre du terminal ou de VS Code ; sinon ouvre VS Code sur le dossier. Mettre une fenêtre au premier plan se fait dans l'app (c'est elle qui a reçu le clic). *(À essayer en vrai.)*
4. ✅ Installation des hooks : l'aperçu montre aussi le nouveau hook de questions. **Rien n'est écrit dans les réglages de l'utilisateur sans lui.** *(`hooks.status` dit aussi `upToDate`.)*

### 2. Front : les interactions

**État (8 octobre, après-midi)** : le sous-agent front a été coupé par la limite. On ne lance plus de sous-agents en parallèle (trop de jetons) : le reste se fait **une sous-tâche à la fois, supervisée par l'utilisateur**. Fait et fusionné : le moteur (`line_diff.dart` : diff de lignes Myers borné et plié ; `requests.dart` : `requestQueue`, l'ordre des demandes, branché dans `IslandMachine` ; `MikkyProp.mouth` et `puff` pour avaler). Les écrans commencés (carte de question, page des demandes, touches, vue du diff, avalé) sont sur la branche `worktree-agent-a856394d1274baacc`, commit « En cours », **pas finis ni testés** : à reprendre sous-tâche par sous-tâche (Ctrl + clic, carte de question, notch droit à la demande, essai réel, diff, Kirby).

Propriétaire de : `app/lib/island/`, `app/lib/side/` (sauf ce qui est à la droite), `app/lib/motion/`, `app/lib/ui/`, `packages/mikky_engine/lib/src/mikky/` et `anim/`, le dépôt de fichiers natif.

1. **Le notch va droit à la demande** : quand quelque chose attend (question, permission), l'île ouverte montre la demande la plus prioritaire (questions et permissions d'abord, puis erreurs, puis limites ; les plus anciennes d'abord), « 1/3 », puis la suivante après la réponse, puis revient où on était. Clavier : Y / N / T (Toujours), 1–4 pour les choix, Entrée, Échap.
2. **La carte de question** : choix simple (un clic répond), multi-choix (cocher puis Envoyer), « Autre… » (texte libre), « Répondre dans le terminal ». Barre plate (`AnswerBar`), jamais de capsules `MButton`.
3. **La vue du diff** : un clic sur `+N −M` (carte de demande, fil de l'agent) ouvre le diff du fichier (lignes, couleurs, mono, défilement) ; le calcul du diff en Dart pur dans le moteur, testé.
4. **Mikky avale le fichier (Kirby)** : chorégraphie sur la planche Mikky (barre de temps, ralenti), puis branchée : le fichier glissé au-dessus de l'île → Mikky ouvre la bouche et gonfle ; lâché → il avale, garde une forme pleine un instant ; puis « À quel agent ? » (les agents + Nouvelle tâche) ; le chemin du fichier part avec le message.
5. **Ctrl + clic** sur un agent (tuile, tâche regardée, carte de demande, ligne) → `AgentsService.reveal`.

### 3. Le notch de droite

Propriétaire de : la disposition de droite dans `app/lib/home/` (`HomeLayout.right`), les planches Notch Right et Accueil Right, leurs goldens.

Faire de la droite la vraie version verticale du notch du haut (« Côte à côte », 730 × 216) : Mikky qui regarde la dernière tâche (le logiciel, son titre, ses étapes), les autres applications en tuiles avec leur logiciel, les points gris vivants, les pages en fondu, + Nouvelle tâche ; texte posé comme une app de téléphone, jamais tourné. Le même `HomeView` ; d'abord sur la planche Notch Right, à côté de l'accueil de droite actuel, pour que l'utilisateur compare.

- [x] Planche Notch Right : trois mises en page (Empilé, Deux colonnes, Taille de la page) à côté de l'accueil d'avant, toutes les situations, clair et sombre (8 octobre).
- [x] Dans l'app : « Empilé » dans `HomeView` (`HomeLayout.rightNotch`, 320 × 416, page d'un agent 344 × 520) ; retour à l'ancienne droite par `IslandMetrics.rightNotch = false`.
- [x] Images de test refaites et regardées ; `design.md` (« Notch ») et `reprise.md` à jour.
- [ ] **Choix de l'utilisateur** sur la planche, puis essai dans l'app (bundle).

### Règles pour les trois

- `CLAUDE.md`, `reprise.md`, `design.md` d'abord. Parler en français dans les docs.
- Chaque changement visuel passe par les planches (`--kit`), goldens refaites **et regardées** ; décisions dans `design.md` (marquées « à valider »).
- Tests : `cargo test`, `dart.bat test` dans chaque paquet, `flutter.bat test` dans `app/`.
- Ne jamais toucher aux réglages de Claude / Codex de l'utilisateur, ni relancer `mikkyd` en service, ni piloter la souris ou le clavier.
- Rien de committé qui ne soit à nous (les sons restent hors de git).

## Ensuite, dans l'ordre

1. **Fusionner, construire le bundle, installer les hooks avec l'utilisateur**, puis l'essai réel : une permission (Oui, Non, Terminal), une question à choix, une question multi-choix, Ctrl + clic, un fichier avalé.
2. **Le notch qu'on utilise tous les jours** : répondre depuis une tuile, la carte « terminé » (résumé et fichiers), la page Réglages qui remplace le menu du clic droit.
3. **Le premium là où il se voit** : la tuile qui devient la page de l'agent, le jeu de ressorts, puis les moments de Mikky (`plans/2026-10-05-visuel-et-son.md` §1), les sons.
4. **GitHub dans `mikkyd`** (jeton dans le coffre) : PR, CI, revues ; puis OpenCode et Gemini CLI (ACP).
5. **Les fondations du « Discord »** : de vraies tables SQLite (projets, missions, fils, messages, décisions, journal) avec migrations, et le protocole écrit en schéma. Le « Discord » n'est qu'un autre écran sur ces données, comme le notch et plus tard le téléphone.
6. **Le « Discord »** (la grande fenêtre R4 reprise) : la file de décisions d'abord, puis les missions, la présence, le kanban qui se met à jour tout seul (`idees.md` §10).
7. **La fabrique de logiciel** (`idees.md` §11, 2026-10-11) : un projet de code piloté dans le « Discord » vit dans un environnement défini : ticket = issue GitHub avec critères d'acceptation, un agent par ticket dans un espace isolé avec sa propre URL de test, la PR comme point de contrôle, la CI/CD visible dans le salon, la skill de vérification du projet, la relecture ciblée, l'échelle de confiance réglée par projet. Les tables de l'étape 5 doivent déjà prévoir le projet, son environnement et ses règles.
