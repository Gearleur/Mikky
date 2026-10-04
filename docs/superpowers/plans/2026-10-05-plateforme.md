# Plan de la plateforme : ton environnement, la performance, la sécurité, le cloud

Écrit le 2026-10-04 (demande : « en termes de perf, si c'est sur un cloud, faut qu'on y pense aussi ; sans les visuels, je veux que ce soit ultra performant, sécurisé » ; « adapter à mon environnement, à ce que je veux, et penser aux versions futures pour manager des IA dans le cloud comme Replicas »). Rien ici n'est décidé au-delà de ce qui est marqué **fait** ; à relire ensemble avant de commencer une étape. Les specs validées restent la référence : `specs/2026-09-30-mikkyd-design.md` (machines, canal, étapes R0–R7) et `specs/2026-09-29-mvp-design.md`.

## 1. Ton environnement, tel qu'il est

- **Windows 11**, Mikky en île (en haut ou à droite), `mikkyd` démarré avec la session.
- **WSL Ubuntu**, où Claude Code et Codex sont aussi installés ; un `mikkyd` Linux natif y tourne, relié au `mikkyd` Windows.
- **Abonnements seulement** (Claude, ChatGPT/Codex), aucune clé d'API.
- Tu lances des agents **depuis Mikky** (ACP, contrôlés), mais aussi **dans un terminal et VS Code** (sessions extérieures, jusqu'ici seulement observées).
- Tu veux un compagnon **au centre de l'attention** : il réagit, il t'apporte ce qui te demande quelque chose, avec le contexte, au bon moment ; ambiance console portable (sons PSP).

## 2. Ce qui manque pour coller à ton usage (ordre proposé)

1. **Brancher les hooks chez toi** (fait côté code, pas installé) : menu clic droit → « Hooks Claude Code… » puis « Hooks Codex… » ; Mikky montre le diff exact avant d'écrire, garde une copie datée. Ensuite, dans Codex, valider une fois les hooks avec `/hooks`. **À essayer en vrai** : une session Claude dans un terminal Windows qui demande une commande ; Oui depuis l'île ; puis Non ; puis « Répondre dans le terminal ». Même essai avec Codex (son format de commande n'a pas été vu en vrai : `mikkyd` accepte le texte et la liste de mots).
2. **Les hooks dans WSL** : les sessions Claude / Codex lancées **dans WSL** utilisent `~/.claude` et `~/.codex` de Linux. Il faut : le relais `mikky-hook` pour Linux (`build-linux.sh` le compile déjà avec le workspace, mais ne le copie pas encore dans le bundle), un point de contact du `mikkyd` Linux pour lui (aujourd'hui il ne publie pas d'adresse : ajouter un socket Unix en `0600` dans `$XDG_RUNTIME_DIR`), et la page d'installation qui écrit côté WSL. Les demandes remontent par le lien WSL existant, comme les sessions.
3. **Les limites de Claude** : Mikky montre celles de Codex (lues dans ses fichiers), pas celles de Claude. Claude Code les donne à sa `statusLine` (`rate_limits.five_hour` / `seven_day`, offres Pro et Max). Plan : `mikky-hook --statusline` (même relais), qui envoie les pourcentages à `mikkyd` et affiche une ligne courte. On ne l'installe que si tu n'as pas déjà une `statusLine` (sinon on ne remplace rien), avec le même diff.
4. **Sauter au bon endroit** : depuis une demande, « Ouvrir le terminal » ou « Ouvrir dans VS Code » (le hook transmet `TERM_PROGRAM`, `WT_SESSION`, `VSCODE_PID`). Windows Terminal : activer la fenêtre ; VS Code : `code <dossier>` (déjà dans le menu d'un agent).
5. **Sessions extérieures « vivantes »** : avec les hooks installés, `Stop`, `PostToolUse` et `UserPromptSubmit` disent en direct où en est une session lancée ailleurs, sans attendre son fichier. Ça permet de dire « tourne » plutôt que « observée » (règle du MVP : ne pas promettre un processus non vérifié).
6. **Mikky hors de l'île** (comme Mochi sur le bureau) : une seconde petite fenêtre native, Mikky posé où tu veux, qui revient dans l'île à chaque demande. Après la séance visuelle.

## 3. Performance (« ultra performant »)

**Principe gardé** : rien ne tourne quand rien ne se passe. Pas de sondage, des échéances.

Déjà en place :
- île cachée = 0 % de CPU ; 30 images/s au repos, 60 seulement pendant les ressorts ;
- `MikkyDirector` et la table des réactions : de simples calculs aux changements d'agents, une seule échéance (le sommeil) ;
- sons : décodés une fois en mémoire (Media Foundation), joués par XAudio2, **moteur audio arrêté dès que plus rien ne joue** ;
- hooks : un petit exécutable par événement (mesuré **≈ 10 ms** une fois en cache ; 2,6 s au tout premier lancement, l'antivirus l'examine) ; rien n'attend sans écran ; `mikkyd` ne garde que les demandes en cours, en mémoire.

À mesurer, puis corriger (rien sans mesure) :
1. **Coût des hooks pendant une grosse session** : `PostToolUse` à chaque outil. Si c'est sensible, ne garder que `PermissionRequest` et `Stop` (le reste est un confort).
2. **Mémoire de `mikkyd`** (déjà prévu, `reprise.md` étape 3) : résumés par session, événements paginés, files d'envoi bornées. Indispensable avant le distant : un écran lent ne doit jamais faire grossir le démon.
3. **L'île ouverte** : flous en couches, longues conversations (`--perf`), reconstruction de la carte de demande (elle se reconstruit à chaque événement de l'agent suivi, au plus une fois par seconde pour l'heure).
4. **Démarrage** : taille du bundle, temps jusqu'à la première image.

Pour le **distant** (VPS, cloud) :
- **le démon envoie des résumés, pas le trafic brut** : l'état et les dernières actions, et le détail à la demande, page par page ;
- **reprise sans perte** : chaque flux a déjà un numéro de séquence (`run.subscribe` avec `after`) ; à généraliser à tous les flux, pour qu'une reconnexion ne renvoie que ce qui manque ;
- **contre-pression** : files bornées par écran ; un écran trop lent est déconnecté proprement et se resynchronise ;
- **compression** (`permessage-deflate`) seulement à travers le réseau, pas en local ;
- **délais** : une demande de permission qui traverse le réseau garde la même règle (pas de réponse en 105 s → l'agent demande chez lui).

## 4. Sécurité

Ce qui protège aujourd'hui :
- `mikkyd` n'écoute que **127.0.0.1**, avec un jeton de 256 bits gardé dans le **coffre de Windows** pour la session (jamais sur le disque) ; il refuse toute connexion qui vient d'un navigateur (en-tête `Origin`). Le relais des hooks utilise **le même jeton**, lu dans le coffre.
- Les hooks **ne bloquent jamais** Claude ou Codex, et ne décident jamais seuls : une réponse ne part que d'un clic. Pas de « Toujours » par les hooks.
- Les fichiers de configuration (`settings.json`, `hooks.json`) : jamais écrasés ; lus, fusionnés, **diff montré**, écrits seulement si le fichier n'a pas changé depuis l'aperçu (empreinte), **copie datée** avant, écriture par renommage (jamais un fichier à moitié écrit). Désinstaller ne retire que les entrées de Mikky.
- Ce qu'envoient les hooks (commandes, chemins) reste **en mémoire** dans `mikkyd`, coupé à 2 000 caractères par champ, jamais écrit sur le disque ni envoyé ailleurs.
- Sons et autres fichiers de l'utilisateur hors du dépôt public (`.gitignore`).

À faire :
1. **Limite de confiance locale, à dire clairement** : tout programme qui tourne sous ton compte Windows peut lire le jeton du coffre (c'est la limite de Windows elle-même). Défense en plus si besoin : n'accepter `hook.event` que d'un processus `mikky-hook.exe` signé (vérifier l'exécutable au bout de la connexion), et limiter ce qu'un jeton de relais peut appeler (un second jeton « relais » qui n'a droit qu'à `hook.event`).
2. **Ce qui s'affiche est une donnée, jamais un ordre** : les textes des agents (commande, résumé) sont affichés en texte simple, sans lien cliquable ni code exécuté. À garder en règle pour toutes les nouvelles vues, et pour le futur canal entre agents (`mikkyd` spec §7.3).
3. **Chaîne de livraison** : `cargo build --locked` (déjà), puis `cargo audit` et `dart pub outdated` dans une vérification, signature de `mikky.exe`, `mikkyd.exe`, `mikky-hook.exe` (sinon SmartScreen et l'antivirus ralentissent ou bloquent), liste des dépendances (SBOM) avec chaque version.
4. **Mises à jour** : un canal signé (clé de Mikky), vérification avant remplacement ; le relais des hooks est copié dans `%LOCALAPPDATA%\Mikky\bin` à l'installation et remplacé seulement quand il ne sert pas.
5. **Journal d'audit** (déjà dans la spec, idée 53) : qui a autorisé quoi, quand, d'où (île, raccourci, terminal). Utile dès qu'il y a plusieurs machines.

## 5. Le cloud et les versions futures

Les étapes validées restent celles de `mikkyd` (R4–R7). Ce plan les précise pour « manager des IA dans le cloud comme Replicas ».

**Le principe** : **un `mikkyd` par lieu**, l'app ne parle qu'au `mikkyd` du PC, qui relie les autres. Un lieu = où tournent les agents : Windows, WSL, un VPS, et plus tard un service cloud. Un lieu sait dire ce qu'il permet (lancer, suivre, répondre aux permissions, envoyer des fichiers) ; l'app n'affiche que ce qu'il permet (règle déjà suivie pour les sessions extérieures).

**Versions (proposition)** :
- **V1, aujourd'hui → MVP** : île fiable sous Windows et WSL, agents Mikky et sessions extérieures (hooks), demandes avec leur contexte, sons et animations validés ensemble.
- **V2, les équipes sur le PC** (R5–R6) : d'autres harnais (OpenCode, Gemini CLI…), équipes, worktree par agent, canal entre agents par `mikkyd` (identité par le système, droits, journal), après la recherche prévue (A2A, MCP…).
- **V3, le VPS** (R7) : `mikkyd` Linux en service, **tunnel SSH** (aucun port ouvert), jumelage des machines par clés ed25519, messages signés. Les agents du VPS apparaissent comme ceux du PC, avec leur lieu.
- **V4, le cloud « à la Replicas »** : une tâche part d'ici (ou de GitHub / Linear plus tard), tourne dans un **bac à sable jetable** autour d'un dépôt (conteneur sur le VPS d'abord, puis un service), et revient en branche ou PR. Côté Mikky : un **connecteur de lieu** dans `mikkyd`, qui traduit l'API du service en événements de session (`SessionEvent`, le format commun) ; les identifiants du service dans le coffre, jamais dans Flutter. Replicas lui-même serait un de ces connecteurs, si son API le permet (`idees.md` §9) ; rien n'est imposé à toute l'app.
- **V5, ailleurs** : téléphone (Flutter mobile), web servi par `mikkyd`, en TLS avec jumelage par QR code ou sur un réseau privé (WireGuard / Tailscale).

**Ce que le cloud demande déjà, à préparer dès V1** :
1. **Un protocole versionné et documenté** : aujourd'hui « protocole 3 », décrit dans le code. Écrire ses messages une fois (schéma), pour l'app, les relais et les connecteurs.
2. **Les identités** : chaque demande dit d'où elle vient (lieu, session, agent) ; c'est déjà le cas des demandes de hooks (`agent`, `sessionId`, `cwd`, terminal).
3. **Les permissions à distance** : la même file que les hooks (`hooks.rs`), généralisée à tout lieu : une demande, une réponse, un délai, et retour au lieu d'origine sans réponse.
4. **Les coûts et limites par lieu** : abonnement de l'utilisateur ici ; un service cloud aura les siens, affichés à part (`idees.md` §9, consommation).

## 6. Ordre proposé pour les prochaines sessions techniques

1. Essai réel des hooks Claude (Windows), puis Codex ; corriger ce qu'on voit.
2. Hooks dans WSL ; limites de Claude par la `statusLine`.
3. Mémoire bornée de `mikkyd` et mesures (`--perf`, coût des hooks).
4. Signature des binaires et vérification de la chaîne de livraison.
5. Puis la suite validée : R5 (harnais), R6 (équipes), R7 (VPS).
