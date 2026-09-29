# Mikky — le MVP : suivre et lancer Claude Code et Codex

Date : 2026-09-29 · Statut : **proposition, à valider avec l'utilisateur**

## 1. Contexte et intention

L'étape 1 est faite : Mikky et son île tournent sous Windows avec de faux agents (`reprise.md` §1). Le 2026-09-29, le projet a grandi : Mikky devient un compagnon qui suit et pilote nos agents Claude Code et Codex, un « Paperclip plus simple » (`idees.md`). L'UI (`design/prototypes/composants.html`) et l'UX de la petite fenêtre à droite (`design/prototypes/ux-a.html`) sont validées.

Le MVP complet, dans l'ordre voulu par l'utilisateur :

| Partie | Quoi | Dans cette spec |
|---|---|---|
| **A** | Brancher Claude et Codex, et la petite fenêtre (accueil, page d'un agent, nouvel agent) | **en détail** (§3 à §9) |
| B | Gérer Claude et Codex, planifier des tâches (tâches qui se relancent seules) | grandes lignes (§10) |
| C | LocalSend | grandes lignes (§10) |
| D | Classer les mails Gmail avec Laya | grandes lignes (§10) |
| E | Parler : Ctrl + Win maintenus, puis Whisper en local | grandes lignes (§10) |

B à E auront chacune leur petite spec quand on y arrivera. Cette spec sert à valider **A** et l'ordre de la suite.

**La partie A est réussie quand** :
- depuis la petite fenêtre, on lance un Claude ou un Codex, sous Windows ou dans WSL, avec « Demander » ou « Auto », sur un dossier choisi ;
- on voit en direct ce qu'il fait (Suivi et Chat), on lui glisse un message, on l'arrête ;
- une demande de permission arrive dans Mikky (fenêtre **et** île) et on répond Oui / Non ; sans réponse, l'agent attend (jamais d'accord sans clic) ;
- les sessions lancées ailleurs (VS Code, terminal) apparaissent aussi dans l'accueil, sous Windows comme dans WSL ;
- l'île et Mikky prennent l'état de l'agent en focus, comme avec les faux agents ;
- côte à côte avec `ux-a.html` et `composants.html`, on ne voit pas de différence ;
- île cachée et aucun agent qui travaille : 0 % de CPU.

## 2. Hors périmètre de la partie A

`mikkyd` et le VPS, le téléphone, l'app sous Linux (on la prépare seulement, §8), worktrees, tableau de tâches, fichiers et modifs, boucles agentiques, agents qui se parlent, limites d'abonnement détaillées (on affiche juste l'état « limité » quand l'agent le dit), dictée (partie E), Mac.

## 3. Ce qu'on reprend de Paperclip

Paperclip (MIT, https://github.com/paperclipai/paperclip) lance les CLI officiels, déjà connectés par l'utilisateur. Mikky fait pareil et **ne touche jamais aux jetons**. Là où on recopie du code de Paperclip, on garde sa mention de licence.

### 3.1 Claude Code

Mikky se comporte comme un « hôte SDK » : il lance

```
claude --print --input-format stream-json --output-format stream-json --verbose
       --permission-mode <manual | auto> --permission-prompts host
       [--resume <id>] [--model <modèle>]
```

- **Lecture en direct** : chaque ligne de sortie est un événement JSON (début de session avec son id, message de l'assistant, appel d'outil, résultat, fin avec `result`). Référence : `claude-local/src/server/parse.ts` de Paperclip.
- **Messages glissés** : on écrit le message de l'utilisateur sur l'entrée du processus pendant qu'il travaille ; Claude le prend au tour suivant. Le processus reste ouvert : la conversation continue sans relancer.
- **Permissions** : avec `--permission-prompts host`, chaque demande arrive à Mikky (`can_use_tool`) ; Mikky répond oui ou non quand l'utilisateur a cliqué. **Demander** = `--permission-mode manual` ; **Auto** = `--permission-mode auto` (le mode automatique de Claude, choisi par l'utilisateur pour ce lancement).
- **Questions** : l'outil de question de Claude (`AskUserQuestion`) passe aussi par l'hôte ; Mikky l'affiche avec ses choix.
- **Abonnement** : si `ANTHROPIC_API_KEY` n'est pas défini, `claude` utilise le compte sur lequel l'utilisateur est connecté. Mikky ne définit jamais cette variable.

### 3.2 Codex

Deux façons de le lancer ; à trancher par un essai au tout début du plan (§11, question 2) :

- **`codex app-server`** (celle qu'utilise l'extension VS Code) : dialogue JSON sur l'entrée / sortie, avec de vraies demandes d'approbation et plusieurs tours dans le même processus. C'est ce qu'il faut pour **Demander** et pour les messages glissés. Marqué « expérimental » par Codex.
- **`codex exec --json`** (celle de Paperclip, éprouvée) : un tour par processus, `codex exec resume <id>` pour continuer. Pas de demande d'approbation possible : seulement **Auto**.

Permissions : **Demander** = sandbox `workspace-write` + approbations envoyées à Mikky ; **Auto** = `--approve-for-me` (revue automatique de Codex, sandbox `workspace-write`). Jamais `--dangerously-bypass-approvals-and-sandbox`.

### 3.3 Où tourne l'agent : Windows ou WSL

Une **cible par lancement** :

| Cible | Lancement | Sessions surveillées |
|---|---|---|
| Windows | `claude.exe` / `codex` du PATH Windows | `%USERPROFILE%\.claude\projects`, `%USERPROFILE%\.codex\sessions` |
| WSL | `wsl.exe -d Ubuntu --cd <dossier> -- claude …` | `~/.claude/projects`, `~/.codex/sessions` dans Ubuntu |
| Linux (plus tard) | direct | comme WSL |

- Par défaut, la cible se déduit du dossier : `\\wsl.localhost\Ubuntu\…` ou `/home/…` → WSL, `C:\…` → Windows. On peut la changer dans le menu du modèle (§5.3).
- Au démarrage, Mikky vérifie pour chaque cible si `claude` et `codex` sont là et connectés (comme `auth-check.ts` de Paperclip). S'il en manque un, le choix est grisé avec une phrase simple (« Claude n'est pas installé sous Windows »).
- Sur ce PC aujourd'hui : WSL a `claude` et `codex` ; Windows a `codex` mais pas `claude` (§11, question 1).

### 3.4 Arrêter un agent

Le bouton ■ de la page d'un agent arrête l'agent et tout ce qu'il a lancé. Sous Windows : un « job object » qui englobe le processus et ses enfants. Dans WSL : arrêter `wsl.exe` ne suffit pas toujours ; on lance l'agent dans son propre groupe de processus et on arrête ce groupe dans WSL.

## 4. Voir aussi les sessions lancées ailleurs

Claude écrit chaque session dans `~/.claude/projects/<dossier>/<id>.jsonl`, Codex dans `~/.codex/sessions/AAAA/MM/JJ/rollout-….jsonl`. Mikky **surveille ces dossiers** (événements du système de fichiers, sans boucle) et lit la fin des fichiers qui changent.

| Ce qu'on lit | Claude | Codex |
|---|---|---|
| Titre | ligne `ai-title` | premier message de l'utilisateur, raccourci |
| Travaille | dernier message de l'assistant fini par `tool_use`, fichier modifié il y a peu | `task_started` sans `task_complete` |
| Terminé | dernier message fini par `end_turn` | `task_complete` |
| Historique | rien de nouveau depuis 1 jour (à régler) | pareil |

- Ces sessions sont **en lecture seule** : on voit leur Suivi et leur Chat, mais on ne leur répond pas (elles appartiennent à VS Code ou au terminal). Une demande de permission dans une session extérieure ne se voit pas dans ces fichiers : Mikky affiche « Travaille ». Plus tard, un hook Claude Code optionnel pourra prévenir Mikky.
- Une session extérieure **terminée** peut être **continuée dans Mikky** (bouton dans son chat) : Mikky la reprend avec `--resume <id>` (ou `resume <id>` pour Codex), sur la même cible.
- Les sessions lancées par Mikky écrivent aussi ces fichiers : Mikky les reconnaît par leur id et ne les montre qu'une fois.
- **Point à vérifier en premier** : Windows ne reçoit pas toujours les événements de fichiers d'un dossier WSL (`\\wsl.localhost\…`). Si c'est le cas, Mikky lance dans WSL une petite sonde qui surveille ces dossiers (inotify) et lui envoie les changements. Elle ne tourne que pendant que Mikky tourne.

## 5. La petite fenêtre (position « à droite »)

C'est l'île ouverte en position « à droite » (320 × 560, rayon 38), avec le contenu de `ux-a.html`, aux couleurs et formes de `composants.html` (jetons de `mikky-ui.css`, thèmes clair et sombre). La position « en haut » garde l'île actuelle (Focus / Liste) ; la fenêtre des agents n'existe qu'à droite pour le MVP.

### 5.1 Accueil

- Mikky en petit en haut à gauche, titre « Agents ».
- Groupes repliables : **En attente** (contour orange, Oui / Non et la commande directement sur la carte), **Travaillent** (carte grise, ce qu'il fait à l'instant qui défile), **Terminés** (simple trait), **Historique** (replié par défaut).
- Chaque carte : titre, ce qu'il fait, Claude ou Codex, et un petit repère si la session vient d'ailleurs (VS Code, terminal) ou tourne dans WSL.
- Bouton rond noir → en bas à droite : nouvel agent.

### 5.2 Page d'un agent

- **Au travail** : deux vues, **Suivi | Chat**, le choix à moitié dans le champ.
  - **Suivi** : la ligne de métro de ses tâches. Les tâches viennent de la liste de tâches de l'agent (outil de todo de Claude, `update_plan` de Codex) ; s'il n'en a pas, une étape par action notable (lit, modifie, lance). Trait bleu qui avance, halo léger et lent, code en direct sous l'étape en cours (tiré des modifications de fichier de l'agent), messages glissés entre les tâches.
  - **Chat** : l'historique complet en chat normal ; la tâche en cours est une carte qui ramène au Suivi.
- **Tâche finie** : retour au chat normal ; la tâche devient une carte « Tâche terminée » qui se déplie ; la conversation continue (nouveau message = nouveau tour, même session).
- **En attente** : la demande (commande, fichier, question avec ses choix) s'affiche en bas du fil, avec Oui / Non.
- Bouton ■ en haut à droite pour arrêter l'agent.

### 5.3 Nouvel agent

- Le chat vide « Qu'est-ce qu'on lance ? », le champ, et à moitié dans le champ : **dossier** (récents + parcourir) et **modèle**.
- Le menu du modèle contient aussi, en dessous : **Où** (Windows / WSL, déduit du dossier) et **Permissions** (Demander par défaut / Auto). Mikky retient les derniers choix par dossier.
- En envoyant, on arrive sur la page de l'agent, en Suivi.

### 5.4 Le champ de saisie

Style « Champ » (gris en creux), micro et flèche d'envoi à droite, grandit jusqu'à 5 lignes. Entrée envoie, Maj + Entrée va à la ligne. Le micro est affiché mais ne fait rien avant la partie E. Pour taper, la fenêtre de l'overlay prend le clavier quand on clique dans le champ (canal `activate`) et le rend quand l'île se ferme.

### 5.5 L'île et Mikky

L'île affiche les vrais agents à la place des faux : même `AgentSource`, mêmes règles (`IslandMachine`), même Oui / Non. Le mode Démo reste dans le menu. Les états de l'agent en focus donnent les transformations de Mikky déjà validées (travaille, réfléchit, attend ton feu vert, terminé…).

## 6. Correspondance des états

| État dans Mikky | Claude | Codex |
|---|---|---|
| réfléchit | début de tour, texte de l'assistant en cours | tour commencé, raisonnement |
| cherche | outils de recherche (Grep, Glob, WebSearch, WebFetch, lecture) | commande de recherche (`rg`, `grep`…) |
| travaille | autres outils (Edit, Write, Bash…) | commande, modification de fichier |
| feu vert | `can_use_tool` reçu | demande d'approbation reçue |
| question | `AskUserQuestion` | — |
| erreur | `result` en erreur, processus arrêté anormalement | erreur de tour |
| limité | message de limite d'abonnement | erreur de limite |
| terminé | `result` réussi | tour terminé |

Le détail affiché (en mono) : la commande, le fichier, la question ou le résultat.

## 7. Architecture

```
packages/
├── mikky_engine/        # Dart pur, sans Flutter (existe)
│   └── agents/          #   + modèle de session, événements, lecteurs des formats Claude et Codex
└── mikky_agents/        # nouveau : Dart + dart:io, sans Flutter
    ├── runner/          #   lancer Claude / Codex, Windows ou WSL, arrêter, écrire et lire les JSON
    ├── watch/           #   surveiller les sessions extérieures (+ la sonde WSL si besoin)
    ├── check/           #   CLI installés et connectés, par cible
    └── real_source.dart #   RealAgentSource : implémente AgentSource
app/lib/
├── ui/                  # jetons et composants de composants.html (boutons, sélecteurs, champ, cartes…)
└── side/                # accueil, page d'un agent (Suivi, Chat), nouvel agent
```

- **Un seul format d'événements** dans le moteur (`SessionEvent` : message de l'utilisateur, texte de l'assistant, appel d'outil, résultat, liste de tâches, demande de permission, question, fin, erreur). Quatre lecteurs le produisent : sortie en direct de Claude, fichier de session de Claude, sortie de Codex, fichier de session de Codex. Ils sont testés avec de vrais fichiers enregistrés (nettoyés de tout contenu privé).
- `Agent` gagne : fournisseur (Claude / Codex), cible (Windows / WSL), origine (Mikky / extérieure), dossier, id de session, permissions.
- **Ce que Mikky garde sur le disque** : la liste de ses agents (id de session, cible, dossier, titre, permissions), les dossiers récents et les derniers choix, dans `%APPDATA%\Mikky\agents.json`. Pas les conversations : elles restent dans les fichiers de Claude et Codex, relus au besoin.
- **Quand on quitte Mikky** : s'il y a des agents au travail, Mikky demande confirmation ; ils s'arrêtent avec lui (pas de `mikkyd` pour le MVP). Fermer la fenêtre ou l'île ne les arrête pas. Au prochain lancement, ils sont dans Historique et on peut les continuer.

## 8. Préparer Linux sans le faire

`mikky_agents` n'utilise que `dart:io` ; les chemins et la façon de lancer dépendent de la cible, pas de Windows. Seul l'overlay natif (`app/windows/runner/`) sera à refaire pour Linux, plus tard.

## 9. Tests et vérifications

- Moteur : lecteurs des quatre formats, correspondance des états, règles de l'accueil (quel agent dans quel groupe), avec des fichiers enregistrés.
- `mikky_agents` : un faux `claude` / `codex` (petit script qui rejoue un fichier enregistré) pour tester lancement, permissions, messages glissés, arrêt, sans dépenser d'abonnement.
- UI : goldens de chaque écran en clair et en sombre, comparés aux captures des maquettes (`#calme`).
- À la main, sur ce PC : un vrai Claude dans WSL, un vrai Codex sous Windows et dans WSL, une session VS Code visible dans l'accueil.
- CPU mesuré île cachée, agents arrêtés.

## 10. La suite du MVP (grandes lignes)

- **B. Gérer Claude et Codex, planifier des tâches** : voir l'état de connexion et les limites, renommer, archiver ; **tâches planifiées** (« chaque matin à 9 h, trie les issues ») qui lancent un agent avec une consigne, un dossier et des permissions. Elles tournent tant que Mikky est ouvert (réveil à l'heure prévue, sans boucle) ; une tâche manquée pendant que le PC était éteint se lance au démarrage, ou pas (à choisir).
- **C. LocalSend** : Mikky parle le protocole LocalSend (port 53317, ou un autre si l'app LocalSend tourne aussi) ; recevoir un fichier et le donner à un agent ou le ranger dans un projet ; envoyer un fichier au téléphone.
- **D. Mails** : lecture seule par IMAP (mot de passe d'application Gmail dans le coffre de Windows), classement en local avec Laya (Python), modèle chargé seulement pendant le tri.
- **E. Parler** : Ctrl + Win maintenus ou le micro du champ ; le texte s'écrit dans le champ ; Whisper en local.

## 11. Questions pour l'utilisateur

1. **Claude sous Windows** : il n'est pas installé en ligne de commande. On l'installe (`npm i -g @anthropic-ai/claude-code` ou l'installeur officiel), ou on commence avec Claude seulement dans WSL ?
2. **Codex et « Demander »** : on essaie d'abord `codex app-server` (expérimental, mais seul moyen d'avoir Oui / Non et les messages glissés avec Codex). Si l'essai échoue : Codex seulement en Auto pour le MVP. D'accord ?
3. **Sessions extérieures en lecture seule**, avec « Continuer dans Mikky » une fois terminées : ça te va ?
4. **Où et Permissions dans le menu du modèle** (§5.3), plutôt que deux options de plus à moitié dans le champ : ça te va ?
5. **La fenêtre des agents seulement en position « à droite »** pour le MVP : ça te va ?
