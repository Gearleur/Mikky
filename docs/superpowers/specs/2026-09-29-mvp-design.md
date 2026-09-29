# Mikky — le MVP : suivre et lancer Claude Code et Codex

Date : 2026-09-29 · Statut : **validée par l'utilisateur le 2026-09-29**

## 1. Contexte et intention

L'étape 1 est faite : Mikky et son île tournent sous Windows avec de faux agents (`reprise.md` §1). Le 2026-09-29, le projet a grandi : Mikky devient un compagnon qui suit et pilote nos agents Claude Code et Codex, un « Paperclip plus simple » (`idees.md`). L'UI (`design/prototypes/composants.html`) et l'UX de la petite fenêtre à droite (`design/prototypes/ux-a.html`) sont validées.

Le MVP complet, dans l'ordre voulu par l'utilisateur :

| Partie | Quoi | Dans cette spec |
|---|---|---|
| **A** | Brancher Claude et Codex (lancement, connexion, permissions), et la petite fenêtre (accueil, page d'un agent, nouvel agent) | **en détail** (§3 à §9) |
| B | Gérer Claude et Codex, planifier des tâches (tâches qui se relancent seules) | grandes lignes (§10) |
| C | LocalSend | grandes lignes (§10) |
| D | Classer les mails Gmail avec Laya | grandes lignes (§10) |
| E | Parler : Ctrl + Win maintenus, puis Whisper en local | grandes lignes (§10) |

B à E auront chacune leur petite spec quand on y arrivera. Cette spec sert à valider **A** et l'ordre de la suite.

**La partie A est réussie quand** :
- depuis la petite fenêtre, on lance un Claude ou un Codex, **sous Windows ou dans WSL**, avec « Demander » ou « Auto », sur un dossier choisi ;
- si un outil n'est pas connecté, Mikky propose la connexion, comme Paperclip, sans jamais toucher aux jetons ;
- on voit en direct ce qu'il fait (Suivi et Chat), on lui glisse un message, on l'arrête ;
- une demande de permission arrive dans Mikky (fenêtre **et** île) et on répond Oui / Non ; sans réponse, l'agent attend (jamais d'accord sans clic) ;
- les sessions lancées ailleurs (VS Code, terminal) apparaissent aussi dans l'accueil, sous Windows comme dans WSL ;
- l'île et Mikky prennent l'état de l'agent en focus, comme avec les faux agents ;
- côte à côte avec `ux-a.html` et `composants.html`, on ne voit pas de différence ;
- île cachée et aucun agent qui travaille : 0 % de CPU.

## 2. Hors périmètre de la partie A

`mikkyd` et le VPS, le téléphone, l'app sous Linux (on la prépare seulement, §8), la position « en haut » pour la fenêtre des agents, worktrees, tableau de tâches, fichiers et modifs, boucles agentiques, agents qui se parlent, répondre aux sessions extérieures (§4.2, plus tard), limites d'abonnement détaillées (on affiche juste l'état « limité » quand l'agent le dit), dictée (partie E), Mac.

## 3. Brancher Claude et Codex comme Paperclip

Paperclip (MIT, https://github.com/paperclipai/paperclip, adaptateurs `packages/adapters/claude-local` et `codex-local`) lance les outils officiels, déjà connectés par l'utilisateur. Mikky fait pareil et **ne touche jamais aux jetons**.

**Deux principes (validés le 2026-09-29)** :
- **Pas d'API** : seulement les abonnements de l'utilisateur, à travers les outils officiels connectés (comme Paperclip sans clé d'API). Mikky ne gère aucune clé d'API.
- **Mikky n'est pas un harnais d'agents** (comme Hermes ou OpenClaw) : il ne fait tourner ni modèle ni boucle d'agent lui-même. Il lance Claude Code et Codex, les suit, et passe leurs demandes à l'utilisateur. Là où on recopie du code de Paperclip, on garde sa mention de licence.

### 3.1 Par défaut : ACP, le même protocole pour les deux

Aujourd'hui, Paperclip fait passer **Claude et Codex par ACP** (Agent Client Protocol, le protocole de Zed) par défaut, et garde la ligne de commande en secours. Mikky fait pareil :

- deux petits adaptateurs officiels, `claude-agent-acp` (`@agentclientprotocol/claude-agent-acp`) et `codex-acp` (`@agentclientprotocol/codex-acp`), lancent le vrai Claude Code et le vrai Codex, avec le compte de l'utilisateur ;
- Mikky leur parle en JSON sur l'entrée / sortie (JSON-RPC) : **un seul code pour les deux agents** ;
- ce que le protocole donne, et dont Mikky a besoin :

| Besoin de Mikky | ACP |
|---|---|
| Lancer, continuer | `session/new`, `session/prompt` ; `session/load` pour reprendre une session |
| Lire en direct | `session/update` : texte, appels d'outils avec leur état, **modifications de fichier (diff)** |
| La ligne de métro | `session/update` de type `plan` : la liste de tâches de l'agent |
| Permissions | `session/request_permission` → Oui / Non dans Mikky |
| Messages glissés | un nouveau `session/prompt` pendant le travail (à vérifier : file d'attente ou arrêt du tour) |
| Arrêter | `session/cancel`, puis arrêt du processus |
| Demander ou Auto | `session/set_mode` (modes proposés par l'agent) |

Paperclip, lui, répond « oui à tout » aux permissions. Mikky, non : **Demander** (par défaut) envoie chaque demande à l'utilisateur ; **Auto** met l'agent dans son mode automatique (Claude : le mode `auto` ; Codex : la revue automatique, sandbox `workspace-write`), seulement si l'utilisateur l'a choisi pour ce lancement. Jamais `bypassPermissions` ni `--dangerously-bypass-approvals-and-sandbox`.

Les adaptateurs demandent Node (`claude-agent-acp` : Node ≥ 22). Mikky utilise **son propre Node** là où celui du système est trop vieux (choix de l'utilisateur du 2026-09-29 : dans WSL, Node 24 dans `~/.local/share/mikky/node`, le Node 18 d'Ubuntu n'est pas touché), et installe les deux adaptateurs avec npm dans son propre dossier, par cible, la première fois, en le disant à l'utilisateur.

Modes vérifiés pendant l'essai A0 (plan, « Résultat ») : **Demander** = Claude `default` (Manual), Codex `read-only` ; **Auto** = Claude `auto`, Codex `agent` (Auto review). Claude peut refuser Auto selon le modèle et passer en `acceptEdits` : Mikky affiche toujours le mode réel. Avec Codex, **« Non » arrête le tour** ; l'utilisateur écrit ensuite ce qu'il veut à la place.

### 3.2 En secours : la ligne de commande, comme Paperclip

Si un adaptateur ACP manque ou casse, Mikky lance l'outil directement, comme le mode `cli` de Paperclip :

- **Claude** : `claude --print --input-format stream-json --output-format stream-json --verbose --permission-mode <manual | auto> --permission-prompts host [--resume <id>]`. Les permissions arrivent quand même à Mikky (`can_use_tool`), et les messages glissés passent par l'entrée.
- **Codex** : `codex exec --json -c sandbox_mode="workspace-write"`, `codex exec resume <id>` pour continuer. Pas de demande de permission possible : **Auto seulement**, et Mikky le dit.

### 3.3 La connexion, comme Paperclip

- Au démarrage, puis au besoin, Mikky vérifie **pour chaque cible** si l'outil est installé et connecté : `claude auth status` (JSON : connecté, type d'abonnement) et `codex login status` (comme `auth-check.ts` de Paperclip).
- **Codex pas connecté** : Mikky lance `codex login --device-auth` (dans un pseudo-terminal, comme `device-login-runner.ts` de Paperclip), affiche le lien et le code dans la fenêtre, et attend. Codex garde son identifiant lui-même (`~/.codex/auth.json`) ; Mikky ne lit ni n'écrit jamais ce fichier, et n'écrit jamais le code dans un journal.
- **Claude pas connecté** : Mikky lance `claude auth login`, qui ouvre le navigateur ; Claude garde son identifiant lui-même. Mikky ne définit jamais `ANTHROPIC_API_KEY` : c'est l'abonnement qui sert.
- On ne reprend **pas** le cache d'identifiants de Paperclip (`CODEX-AUTH-CACHE.md`) : il sert à ses bacs à sable distants, pas à nous.
- État sur ce PC le 2026-09-29 :

| | Windows | WSL (Ubuntu) |
|---|---|---|
| Claude | 2.1.284, installé ce jour (`C:\Users\alexa\.local\bin\claude.exe`), connecté (Pro) | 2.1.284, connecté |
| Codex | 0.153.4, connecté (ChatGPT) | 0.153.4, **pas connecté** |

### 3.4 Où tourne l'agent : Windows ou WSL

Une **cible par lancement** :

| Cible | Lancement | Sessions surveillées |
|---|---|---|
| Windows | l'adaptateur (ou l'outil) du PATH Windows | `%USERPROFILE%\.claude\projects`, `%USERPROFILE%\.codex\sessions` |
| WSL | `wsl.exe -d Ubuntu --cd <dossier> -- …` | `~/.claude/projects`, `~/.codex/sessions` dans Ubuntu |
| Linux (plus tard) | direct | comme WSL |

Par défaut, la cible se déduit du dossier : `\\wsl.localhost\Ubuntu\…` ou `/home/…` → WSL, `C:\…` → Windows. On peut la changer dans le menu du modèle (§5.3). Si l'outil n'est pas là ou pas connecté sur une cible, le choix affiche une phrase simple et le bouton de connexion (§3.3).

### 3.5 Arrêter un agent

Le bouton ■ de la page d'un agent arrête l'agent et tout ce qu'il a lancé : d'abord `session/cancel`, puis le processus. Sous Windows : un « job object » qui englobe le processus et ses enfants. Dans WSL : arrêter `wsl.exe` ne suffit pas toujours ; on lance l'agent dans son propre groupe de processus et on arrête ce groupe dans WSL.

## 4. Voir aussi les sessions lancées ailleurs

### 4.1 Pour le MVP : les voir

Claude écrit chaque session dans `~/.claude/projects/<dossier>/<id>.jsonl`, Codex dans `~/.codex/sessions/AAAA/MM/JJ/rollout-….jsonl`. Mikky **surveille ces dossiers** (événements du système de fichiers, sans boucle) et lit la fin des fichiers qui changent.

| Ce qu'on lit | Claude | Codex |
|---|---|---|
| Titre | ligne `ai-title` | premier message de l'utilisateur, raccourci |
| Travaille | dernier message de l'assistant fini par `tool_use`, fichier modifié il y a peu | `task_started` sans `task_complete` |
| Terminé | dernier message fini par `end_turn` | `task_complete` |
| Historique | rien de nouveau depuis 1 jour (à régler) | pareil |

- Ces sessions sont **en lecture seule** pour le MVP : on voit leur Suivi et leur Chat, sans leur répondre. Une demande de permission dans une session extérieure ne se voit pas dans ces fichiers : Mikky affiche « Travaille ».
- Une session extérieure **terminée** peut être **continuée dans Mikky** (bouton dans son chat) : Mikky la reprend (`session/load`, ou `--resume <id>` / `resume <id>`) sur la même cible.
- Les sessions lancées par Mikky écrivent aussi ces fichiers : Mikky les reconnaît par leur id et ne les montre qu'une fois.
- **Vérifié pendant l'essai A0** : Windows ne reçoit **aucun** événement de fichiers d'un dossier WSL (`\\wsl.localhost\…`). Mikky lance donc dans WSL une petite sonde (un script avec son Node privé, `fs.watch`, inotify) qui surveille ces dossiers et lui envoie une ligne par changement. Elle ne tourne que pendant que Mikky tourne.
- `session/list` d'ACP liste aussi les sessions de Claude lancées ailleurs (avec titre et date), et `session/load` rejoue leur fil : utile pour afficher le Chat d'une session extérieure.

### 4.2 Plus tard : travailler dessus (souhaité par l'utilisateur, même si c'est compliqué)

Pistes, à étudier après le MVP :
- **Oui / Non depuis Mikky pour une session de VS Code ou du terminal** : un hook Claude Code (`PermissionRequest`), installé avec l'accord de l'utilisateur dans ses réglages, demande à Mikky et attend sa réponse. La session reste dans VS Code, Mikky ne fait que répondre.
- **Être prévenu** quand une session extérieure attend ou a fini : hook `Notification` / `Stop` de Claude, `notify` de Codex.
- **Lui écrire pendant qu'elle travaille** : pas possible depuis l'extérieur aujourd'hui sans que VS Code ou le terminal le permette ; à surveiller (canaux de Claude Code, `codex app-server` partagé que liste `codex agents`).

## 5. La petite fenêtre (position « à droite »)

C'est l'île ouverte en position « à droite » (320 × 560, rayon 38), avec le contenu de `ux-a.html`, aux couleurs et formes de `composants.html` (jetons de `mikky-ui.css`, thèmes clair et sombre). La position « en haut » garde l'île actuelle (Focus / Liste) ; la fenêtre des agents n'existe qu'à droite pour le MVP.

### 5.1 Accueil

- Mikky en petit en haut à gauche, titre « Agents ».
- Groupes repliables : **En attente** (contour orange, Oui / Non et la commande directement sur la carte), **Travaillent** (carte grise, ce qu'il fait à l'instant qui défile), **Terminés** (simple trait), **Historique** (replié par défaut).
- Chaque carte : titre, ce qu'il fait, Claude ou Codex, et un petit repère si la session vient d'ailleurs (VS Code, terminal) ou tourne dans WSL.
- Bouton rond noir → en bas à droite : nouvel agent.

### 5.2 Page d'un agent

- **Au travail** : deux vues, **Suivi | Chat**, le choix à moitié dans le champ.
  - **Suivi** : la ligne de métro de ses tâches. Les tâches viennent du plan de l'agent (`plan` d'ACP, qui reprend l'outil de todo de Claude et `update_plan` de Codex) ; s'il n'en a pas, une étape par action notable (lit, modifie, lance). Trait bleu qui avance, halo léger et lent, code en direct sous l'étape en cours (les diffs de l'agent), messages glissés entre les tâches.
  - **Chat** : l'historique complet en chat normal ; la tâche en cours est une carte qui ramène au Suivi.
- **Tâche finie** : retour au chat normal ; la tâche devient une carte « Tâche terminée » qui se déplie ; la conversation continue (nouveau message = nouveau tour, même session).
- **En attente** : la demande (commande, fichier, question avec ses choix) s'affiche en bas du fil, avec Oui / Non.
- Bouton ■ en haut à droite pour arrêter l'agent.

### 5.3 Nouvel agent

- Le chat vide « Qu'est-ce qu'on lance ? », le champ, et à moitié dans le champ : **dossier** (récents + parcourir) et **modèle**.
- **Pas de Haiku** dans les modèles proposés (décision du 2026-09-29 : il se comporte à part, par exemple il refuse le mode Auto).
- Le menu du modèle contient aussi, en dessous : **Où** (Windows / WSL, déduit du dossier) et **Permissions** (Demander par défaut / Auto). Mikky retient les derniers choix par dossier.
- En envoyant, on arrive sur la page de l'agent, en Suivi.

### 5.4 Le champ de saisie

Style « Champ » (gris en creux), micro et flèche d'envoi à droite, grandit jusqu'à 5 lignes. Entrée envoie, Maj + Entrée va à la ligne. Le micro est affiché mais ne fait rien avant la partie E. Pour taper, la fenêtre de l'overlay prend le clavier quand on clique dans le champ (canal `activate`) et le rend quand l'île se ferme.

### 5.5 L'île et Mikky

L'île affiche les vrais agents à la place des faux : même `AgentSource`, mêmes règles (`IslandMachine`), même Oui / Non. Le mode Démo reste dans le menu. Les états de l'agent en focus donnent les transformations de Mikky déjà validées (travaille, réfléchit, attend ton feu vert, terminé…).

## 6. Correspondance des états

| État dans Mikky | Ce qui le déclenche |
|---|---|
| réfléchit | début de tour, texte ou raisonnement de l'agent en cours |
| cherche | outil de recherche ou de lecture (ACP : genre `search`, `read`, `fetch`) |
| travaille | autre outil (ACP : `edit`, `execute`, `delete`, `move`…) |
| feu vert | demande de permission reçue |
| question | question de l'agent avec des choix (outil de question de Claude) |
| erreur | tour en erreur, processus arrêté anormalement |
| limité | message de limite d'abonnement |
| terminé | fin de tour réussie |

Le détail affiché (en mono) : la commande, le fichier, la question ou le résultat.

## 7. Architecture

```
packages/
├── mikky_engine/        # Dart pur, sans Flutter (existe)
│   └── agents/          #   + modèle de session, événements, lecteurs (ACP, fichiers de session, secours CLI)
└── mikky_agents/        # nouveau : Dart + dart:io, sans Flutter
    ├── acp/             #   client ACP (JSON-RPC sur l'entrée / sortie)
    ├── runner/          #   lancer, Windows ou WSL, secours CLI, arrêter
    ├── auth/            #   installé ? connecté ? connexion (device auth, auth login)
    ├── watch/           #   surveiller les sessions extérieures (+ la sonde WSL si besoin)
    └── real_source.dart #   RealAgentSource : implémente AgentSource
app/lib/
├── ui/                  # jetons et composants de composants.html (boutons, sélecteurs, champ, cartes…)
└── side/                # accueil, page d'un agent (Suivi, Chat), nouvel agent, connexion
```

- **Un seul format d'événements** dans le moteur (`SessionEvent` : message de l'utilisateur, texte de l'agent, appel d'outil, résultat, diff, plan, demande de permission, question, fin, erreur). Les lecteurs le produisent depuis ACP, depuis les fichiers de session de Claude et de Codex, et depuis la sortie des deux secours CLI. Ils sont testés avec de vrais enregistrements (nettoyés de tout contenu privé).
- `Agent` gagne : fournisseur (Claude / Codex), cible (Windows / WSL), origine (Mikky / extérieure), dossier, id de session, permissions.
- **Ce que Mikky garde sur le disque** : la liste de ses agents (id de session, cible, dossier, titre, permissions), les dossiers récents et les derniers choix, dans `%APPDATA%\Mikky\agents.json`. Pas les conversations : elles restent dans les fichiers de Claude et Codex, relus au besoin. Aucun identifiant.
- **Quand on quitte Mikky** : s'il y a des agents au travail, Mikky demande confirmation ; ils s'arrêtent avec lui (pas de `mikkyd` pour le MVP). Fermer la fenêtre ou l'île ne les arrête pas. Au prochain lancement, ils sont dans Historique et on peut les continuer.

## 8. Préparer Linux sans le faire

`mikky_agents` n'utilise que `dart:io` ; les chemins et la façon de lancer dépendent de la cible, pas de Windows. Seul l'overlay natif (`app/windows/runner/`) sera à refaire pour Linux, plus tard.

## 9. Tests et vérifications

- Moteur : lecteurs, correspondance des états, règles de l'accueil (quel agent dans quel groupe), avec des enregistrements.
- `mikky_agents` : un faux agent ACP et un faux `claude` / `codex` (petits scripts qui rejouent un enregistrement) pour tester lancement, permissions, messages glissés, arrêt et connexion, sans dépenser d'abonnement.
- UI : goldens de chaque écran en clair et en sombre, comparés aux captures des maquettes (`#calme`).
- À la main, sur ce PC : un vrai Claude et un vrai Codex, sous Windows et dans WSL ; la connexion de Codex dans WSL ; une session VS Code visible dans l'accueil.
- CPU mesuré île cachée, agents arrêtés.

## 10. La suite du MVP (grandes lignes)

- **B. Gérer Claude et Codex, planifier des tâches** : voir l'état de connexion et les limites, renommer, archiver ; **tâches planifiées** (« chaque matin à 9 h, trie les issues ») qui lancent un agent avec une consigne, un dossier et des permissions. Elles tournent tant que Mikky est ouvert (réveil à l'heure prévue, sans boucle) ; une tâche manquée pendant que le PC était éteint se lance au démarrage, ou pas (à choisir). Et travailler sur les sessions extérieures (§4.2).
- **C. LocalSend** : Mikky parle le protocole LocalSend (port 53317, ou un autre si l'app LocalSend tourne aussi) ; recevoir un fichier et le donner à un agent ou le ranger dans un projet ; envoyer un fichier au téléphone.
- **D. Mails** : lecture seule par IMAP (mot de passe d'application Gmail dans le coffre de Windows), classement en local avec Laya (Python), modèle chargé seulement pendant le tri.
- **E. Parler** : Ctrl + Win maintenus ou le micro du champ ; le texte s'écrit dans le champ ; Whisper en local.

## 11. Réponses de l'utilisateur (2026-09-29)

1. **Claude sous Windows** : on l'installe (fait le 2026-09-29, installeur officiel) ; on fait **Windows et WSL**.
2. **Codex** : faire comme Paperclip pour la connexion (§3.3). Paperclip passant maintenant par ACP pour Claude et Codex, Mikky fait pareil (§3.1), avec la ligne de commande en secours (§3.2). **Validé** : « le choix ACP est le mieux ».
6. **Pas d'API, pas un harnais** : on ne gère pas les clés d'API pour l'instant, et Mikky n'est pas un logiciel de harnais comme Hermes ou OpenClaw (§3).
3. **Sessions extérieures** : lecture seule pour l'instant, mais l'utilisateur veut pouvoir travailler dessus plus tard, même si c'est compliqué (§4.2).
4. **Où et Permissions dans le menu du modèle** : validé.
5. **Fenêtre des agents seulement en position « à droite »** pour le MVP : validé.
