# Mikky — `mikkyd` : le cerveau en Rust, les machines, le VPS et le canal entre agents

Créé le 2026-09-30. **Statut : proposition, à valider par l'utilisateur.** Rien n'est commencé.

## 1. Ce que l'utilisateur veut (2026-09-30)

- Un peu comme **Replicas** (https://replicas.dev : Claude Code, Codex, OpenCode lancés dans des machines virtuelles du cloud, une tâche part de Slack / Linear / GitHub et revient en PR), mais **avec une app de bureau** : Mikky.
- **D'abord la machine (le PC), ensuite le VPS.**
- **Un canal sécurisé entre agents**, avec des identités et des jetons.
- **Une grande fenêtre** pour gérer les agents en profondeur : choisir le harnais (y compris les harnais open source), plusieurs agents par équipe. L'île flottante continue à côté.
- **Un backend rapide en Rust** pour gérer les agents.
- **La version web : plus tard.**
- **Optimiser l'app.**

Replicas est un produit fermé : on n'a pas trouvé de quoi il est fait, et on ne le copie pas. On garde l'idée : des machines qui font tourner des agents isolés, un seul endroit pour tout voir.

## 2. Rust et Flutter : bons choix ?

**Flutter pour les écrans : oui, on garde.** L'île (shader SDF), les pixels et les animations sont faits sur mesure. Un seul code sert au bureau, au téléphone et, plus tard, au web. Il y a déjà ~11 000 lignes d'interface. Le seul code propre à chaque système est l'overlay natif (`app/windows/runner/`), et c'est déjà prévu. Limite connue : Flutter web est lourd (gros téléchargement), acceptable pour un tableau de bord personnel, et c'est pour plus tard.

**Rust pour `mikkyd` : oui (décidé dès l'étape 4, cf. `CLAUDE.md`).** Il ne rend pas les agents plus rapides : leur temps, c'est le modèle qui réfléchit. Il apporte :
- un seul petit binaire pour Windows et pour Linux (VPS, WSL), sans rien à installer autour, qui tourne des mois sans redémarrer ;
- quelques Mo de mémoire, 0 % de CPU à vide (tout est événementiel) ;
- tokio pour suivre des dizaines d'agents, de fichiers et de connexions en même temps ;
- des bibliothèques de sécurité solides : TLS (rustls), signatures ed25519, SQLite ;
- l'API Windows (job objects, coffre d'identifiants) et Linux (groupes de processus, systemd) proprement.

**Le prix à payer :** réécrire en Rust `packages/mikky_agents` (~1 900 lignes) et les lecteurs de sessions du moteur (~1 000 lignes), et décrire une fois les types échangés entre Rust et Dart (§5).

On garde l'autre option en tête, sans la recommander : un démon en Dart compilé (`dart compile exe`) réutiliserait tout le code, mais serait plus lourd, avec moins de bibliothèques réseau et de sécurité, et nous éloignerait du Rust voulu pour le VPS.

## 3. Qui fait quoi

```
            ┌──────────── PC (Windows) ────────────┐        ┌──── VPS (Linux) ────┐
            │                                      │        │                      │
  île  ─────┤                                      │        │                      │
 (mikky.exe)│  WebSocket local   ┌─────────────┐   │  SSH   │   ┌─────────────┐    │
            ├──────────────────► │   mikkyd    │◄──┼────────┼──►│   mikkyd    │    │
 grande     │  (127.0.0.1 +      │ (PC, « hub »)│   │ tunnel │   │   (VPS)     │    │
 fenêtre ───┤   jeton)           └──┬───┬───┬──┘   │        │   └──┬───┬──────┘    │
 (mikky.exe │                       │   │   │      │        │      │   │           │
  --home)   │        Claude ◄─ACP───┘   │   └─ACP─►Codex     │ Claude  OpenCode ... │
            │        (Windows)          │     (WSL)│        │                      │
            └───────────────────────────┼──────────┘        └──────────────────────┘
                                        │
                              fichiers de session (VS Code, terminal)
```

- **`mikkyd` est le seul à lancer, arrêter et suivre des agents.** Il garde l'état (SQLite), les équipes, les tâches, le journal, les identités. Il tourne même app fermée : il démarre à l'ouverture de la session Windows (tâche planifiée « à la connexion », pas un service Windows, car les agents ont besoin du profil de l'utilisateur, de WSL et de ses connexions Claude / Codex).
- **L'app Flutter n'est qu'un écran.** L'île et la grande fenêtre sont deux clients du même `mikkyd` (deux processus : `mikky.exe` et `mikky.exe --home`). Plus besoin du multi-fenêtre de Flutter : l'état vit dans le démon.
- **L'app ne parle qu'au `mikkyd` du PC.** C'est lui qui se relie aux autres machines (le VPS) et les montre comme les siennes. **Un seul point de contrôle**, donc un seul bouton « tout arrêter ».
- **Le VPS** fait tourner le même binaire (`mikkyd` pour Linux, service systemd, utilisateur `mikky` dédié). Claude et Codex y sont connectés avec l'abonnement de l'utilisateur (connexion par code, comme Codex `--device-auth` aujourd'hui).

**WSL, une machine comme les autres (à choisir, §11) :** au lieu que le `mikkyd` Windows pilote `wsl.exe` et une sonde Node, on lance un `mikkyd` Linux dans WSL, relié au `mikkyd` Windows comme le VPS. On supprime la sonde et les pièges de `wsl.exe` (UTF-16, `bash -l`, chemins). Même code pour WSL et VPS.

## 4. Ce qui va en Rust, ce qui reste en Dart

| Rust (`mikkyd`) | Dart (`app/`, `mikky_engine`) |
|---|---|
| Lancer, arrêter (job object, groupe de processus), Windows / WSL / Linux | Mikky, l'île, `IslandMachine`, les transformations |
| Client ACP, secours CLI | Toute l'interface : île, petite fenêtre, grande fenêtre, planches |
| Connexion des outils (installé ? connecté ? connexion) | `SessionLog` : fil, tours, plan à partir des événements reçus |
| Surveiller les sessions extérieures + les lecteurs (Claude, Codex, ACP) → `SessionEvent` | Notifications Windows, zone de notification |
| Résumé de chaque session (titre, état, ce qu'il fait) pour l'accueil et l'île | Un `DaemonAgentSource` qui implémente `AgentSource` |
| SQLite : agents, équipes, tâches, journal, identités | |
| Canal entre agents, serveur MCP donné aux agents (§7) | |
| API pour les écrans, liaison entre machines (§6) | |

Le démon envoie des **événements déjà normalisés** (`SessionEvent`) et un **résumé** par session. L'app garde `SessionLog`, déjà testé, pour construire le fil. Le téléphone et le web recevront la même chose.

## 5. L'API entre les écrans et `mikkyd`

- **JSON-RPC 2.0 sur WebSocket**, comme ACP : lisible, facile à déboguer, le même pour le local, le téléphone et le web.
- Local : `127.0.0.1` seulement, avec un jeton que `mikkyd` range dans le **coffre de Windows** (règle : aucun secret sur le disque). L'app l'y lit.
- Méthodes (première idée) : `machines.list` · `agents.list` / `agents.subscribe` · `agent.launch` / `prompt` / `answer` / `cancel` / `rename` / `archive` · `session.events` (paginé) · `tools.status` / `tools.login` · puis `teams.*`, `tasks.*`, `bus.*`. Le démon pousse `agent.updated`, `session.event`, `permission.requested`…
- **Les types sont décrits une fois**, dans le crate `mikky-proto` (serde). Un schéma JSON en est tiré (schemars), et les classes Dart sont générées ou écrites avec des tests sur les mêmes enregistrements. Les fixtures de l'essai A0 servent des deux côtés.

## 6. Relier les machines (PC ↔ VPS)

- **Chaque `mikkyd` a une clé de machine ed25519**, créée à l'installation (coffre de Windows sur le PC ; fichier `0600` lisible seulement par l'utilisateur `mikky` sur le VPS, faute de coffre).
- **Première étape : un tunnel SSH.** Le `mikkyd` du VPS n'écoute que sur `127.0.0.1` : aucun port ouvert sur Internet. Le `mikkyd` du PC ouvre le tunnel avec une clé SSH gardée dans le coffre de Windows (idée 22). SSH chiffre et authentifie. On n'invente pas de crypto.
- **Au-dessus du tunnel**, les deux démons se présentent par leurs clés de machine (jumelage une fois : on accepte l'empreinte). Chaque message entre machines est signé : qui l'envoie, pour quel agent.
- **Installer le VPS depuis l'app** : donner l'adresse et la clé SSH ; Mikky copie le binaire, crée l'utilisateur `mikky` et le service systemd, puis vérifie Claude / Codex et leur connexion.
- **Plus tard** (téléphone, web) : `mikkyd` écoute en TLS avec jumelage par QR code (clé de l'appareil), ou derrière un réseau privé (WireGuard / Tailscale) : à choisir le moment venu.

## 7. Le canal entre agents (sécurisé)

### 7.1 Principe

Les agents ne se parlent jamais directement : **tout passe par `mikkyd`**, qui sait qui parle, vérifie qu'il en a le droit, écrit dans le journal, et peut demander à l'utilisateur. Chaque agent reçoit un **serveur MCP `mikky`** (petit processus `mikkyd mcp`, lancé par l'agent lui-même) avec quelques outils : `envoyer`, `demander` (attend une réponse), `déléguer` une tâche, `résultat`, `équipe` (qui est là). Même idée que `vtell` / `vrefer` de VelaTerm et l'idée 10.

### 7.2 Identité : qui parle ?

- Chaque agent lancé a une **identité** : `agent@machine`, son équipe, son rôle, ses droits.
- **Sur la même machine, l'identité vient du système, pas d'un secret.** Le pont MCP se connecte à `mikkyd` par un tube nommé (Windows) ou un socket Unix (Linux). `mikkyd` demande au système quel processus est au bout (`GetNamedPipeClientProcessId` / `SO_PEERCRED`) et dans quel job object ou groupe de processus il est. Or c'est `mikkyd` qui a créé ce job pour cet agent. **Il n'y a pas de jeton que l'agent pourrait lire et fuiter.**
- **Là où ça ne marche pas** (agent dans WSL qui parle au `mikkyd` Windows, si on ne met pas de `mikkyd` dans WSL) : un **jeton par agent**, 256 bits au hasard, gardé haché dans `mikkyd`, limité à cet agent et à ses droits, **révoqué dès que l'agent s'arrête**, donné au seul pont MCP. Pas de JWT ; un jeton opaque suffit en local.
- **Entre machines** : le message porte l'identité de l'agent et la signature ed25519 de sa machine (§6).

### 7.3 Droits et garde-fous

- **Droits par équipe** : un agent parle à son équipe ; parler hors de l'équipe, ou à une autre machine, demande l'accord de l'utilisateur (par défaut, réglable).
- **Déléguer ne donne jamais plus de droits** : une tâche déléguée par un agent en mode Demander ne peut pas lancer un agent en Auto.
- **Les messages d'un autre agent sont des données, pas des ordres** : `mikkyd` les donne à l'agent avec leur origine, pour limiter une injection de consigne qui passerait d'agent en agent.
- Limites : nombre de messages par minute, profondeur de délégation (A délègue à B qui délègue à C…), bouton « tout arrêter ».
- **Tout est dans le journal** : qui a dit quoi à qui, quand (idée 53).

### 7.4 Le format des messages

Une **enveloppe structurée** (de, à, équipe, genre : message / tâche / résultat / question, id de conversation, date, signature) **et un texte libre** pour le contenu. Le détail (délégation, retour du résultat) reste à décider **après la recherche prévue** (A7.7 dans `reprise.md` : A2A, MCP, Agora, MAST…). Cette spec ne fixe que la sécurité.

## 8. Harnais et équipes

- **Un harnais = un outil qui parle ACP** (ou un secours CLI), décrit par un petit fichier dans `mikkyd` : comment le lancer, vérifier qu'il est connecté, où il écrit ses sessions. Claude et Codex deviennent deux fichiers comme les autres ; OpenCode et Gemini CLI (qui parlent ACP) s'ajoutent de la même façon, pi et OpenClaw si c'est possible sans clé d'API.
- **Une équipe** : un nom, un dossier ou un dépôt, des agents avec un rôle (chef, exécutant, relecteur), chacun son harnais, son modèle, ses permissions et son **worktree**. Un canal par équipe (§7), un tableau de tâches. C'est la base des boucles « Chef et équipe » et « Codeur et relecteur » (idées 30-31).
- **Écrire son propre harnais : à trancher (§11).** Aujourd'hui, la règle est « abonnements seulement » et « Mikky n'est pas un harnais ». Un harnais maison devrait appeler le modèle lui-même, donc avec une clé d'API. À vérifier : à notre connaissance, l'abonnement Claude n'est pas prévu pour un harnais tiers. Si on le veut quand même, ce serait un programme à part, qui parle ACP, que Mikky lance comme les autres. Le cœur de Mikky resterait « pas un harnais ».

## 9. La grande fenêtre (« la maison de Mikky », idées §2 A)

`mikky.exe --home` : une fenêtre normale (barre des tâches, redimensionnable), à côté de l'île qui reste le compagnon. On y trouve les machines, les équipes, les harnais, les tâches, le journal, les modifs. **Le design passe d'abord par les planches** (`--kit`), et les décisions vont dans `design.md`.

## 10. Les étapes

Chaque étape se termine par une vérification à l'écran avec l'utilisateur, un commit, et une mise à jour de `reprise.md`.

**R0 — Préparer.** Installer Rust (rustup) sous Windows et dans WSL. Créer l'espace `daemon/` (cargo workspace) : `mikky-proto`, `mikky-acp` (voir si le crate ACP officiel de Zed, `agent-client-protocol`, convient : à vérifier), `mikky-run`, `mikky-watch`, `mikky-store`, `mikky-bus`, `mikky-api`, et le binaire `mikkyd`. Essai : lancer `claude-agent-acp` depuis Rust et recevoir un `session/update`.

**R1 — `mikkyd` fait ce que fait `mikky_agents`, sur le PC.** Lancer / continuer / arrêter Claude et Codex (Windows et WSL), Demander / Auto, Oui / Non / Toujours, questions à choix, connexion des outils, SQLite à la place de `agents.json` (migration au premier lancement). API WebSocket. Côté app : `DaemonAgentSource`, avec l'ancien chemin Dart gardé derrière un réglage jusqu'à ce que tout marche pareil. **Liste de contrôle : tout ce qui marche dans A0 à A7.6.** Tests : le faux agent ACP et les enregistrements, rejoués en Rust.

**R2 — Sessions extérieures en Rust.** Surveillance des fichiers de Claude et Codex (crate `notify`), lecteurs portés depuis le moteur Dart avec les mêmes fixtures, résumés pour l'accueil. WSL : `mikkyd` dans WSL si on le choisit (§3), sinon la sonde actuelle.

**R3 — Les agents vivent sans l'app.** `mikkyd` démarre à l'ouverture de session ; quitter l'app n'arrête plus les agents ; l'app se reconnecte et retrouve tout. On supprime `mikky_agents` et les lecteurs Dart devenus inutiles.

**R4 — La grande fenêtre.** Planches d'abord, puis `mikky.exe --home` : machines, agents, équipes, harnais.

**R5 — Harnais.** Fichiers de description des harnais ; OpenCode et Gemini CLI branchés (c'était le point 1 de la prochaine session).

**R6 — Équipes et canal entre agents, sur le PC.** Après la recherche A7.7 et la spec du format : identités, droits, serveur MCP `mikky`, journal, worktree par agent, tableau de tâches simple.

**R7 — Le VPS.** Binaire Linux (compilé dans WSL), installation par SSH depuis l'app, tunnel, jumelage des machines, agents du VPS dans l'app, messages entre machines signés.

**Plus tard.** Tâches déclenchées par GitHub / Linear et PR à la fin (le côté Replicas), bacs à sable par tâche sur le VPS (conteneurs), téléphone (TLS + QR), web servi par `mikkyd`.

**En parallèle : optimiser l'app.** Mesurer d'abord (`--perf`, release) : le flou en couches des pages d'agent, les longues conversations (markdown reconstruit ?), le démarrage, la taille de l'exe. Corriger ce que les mesures montrent. Avec `mikkyd`, l'app ne lance plus de processus et ne lit plus de fichiers : elle ne fait plus qu'afficher.

## 11. Questions pour l'utilisateur

1. **Écrire nos propres harnais** : on s'en tient aux harnais existants (open source compris), ou tu veux un jour un harnais maison, avec une clé d'API (§8) ?
2. **WSL** : un `mikkyd` dans WSL, comme une machine (recommandé), ou le `mikkyd` Windows qui pilote `wsl.exe` comme aujourd'hui ?
3. **Liaison avec le VPS** : tunnel SSH d'abord (recommandé), ou tout de suite un réseau privé (Tailscale / WireGuard) ?
4. **Messages entre machines** : accord de l'utilisateur par défaut (recommandé), ou libres au sein d'une équipe ?
