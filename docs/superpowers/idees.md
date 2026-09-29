# Mikky — les idées (pour ne pas les perdre)

Créé le 2026-09-29, pendant le brainstorming avec l'utilisateur. Mikky devient un compagnon qui gère nos sessions d'agents : un « Paperclip plus simple », avec nos agents, nos tâches, nos fichiers, LocalSend et un VPS.

**On ne fait pas tout d'un coup.** On commence par le MVP ci-dessous. Tout le reste est gardé ici pour plus tard. L'utilisateur est d'accord avec la liste et l'ordre proposés ; on choisira dans cette liste à chaque nouvelle étape.

## 1. Le MVP (choisi le 2026-09-29)

1. **Lancer Claude Code et Codex depuis la petite fenêtre à droite** (la position « à droite » de l'île, format téléphone) et **voir lequel est en train de travailler**.
2. **LocalSend dans Mikky** : recevoir et envoyer des fichiers avec le téléphone et les autres PC.
3. **Classer nos mails en local** avec **Laya** (https://huggingface.co/convaiinnovations/laya), boîte **Gmail**. Un truc simple ; fonctions plus poussées plus tard.
4. **Designer maintenant tous les composants** (boutons, navigation, champs, listes…) **et leurs animations**, pour être tranquille ensuite. Prototype : `design/prototypes/composants.html`.

### Décisions du 2026-09-29 (après la planche des composants)

- **L'interface (UI) est validée** (`design/prototypes/composants.html`, quelques petits bugs à corriger plus tard). **L'UX est à repenser.**
- **L'activité d'abord** : on veut voir qui travaille et sur quoi. Le chat n'est pas au premier plan.
- **Lancer une tâche** : sur une page à part, avec la **dictée vocale**.
- Les trois onglets du bas (Agents, Partage, Mails) ne sont pas forcément la bonne structure : mails et partage ne sont pas le cœur de l'app.
- **Voir qui travaille : tout le monde**, pas seulement les agents lancés par Mikky (sessions Claude de VS Code et du terminal, sessions Codex). Claude écrit ses sessions dans `~/.claude/projects/`, Codex dans `~/.codex/sessions/AAAA/MM/JJ/` : les surveiller suffit, sans boucle.
- Pistes d'UX : `design/prototypes/ux-activite.html` (A le fil, B les agents en grand, C Mikky au centre, plus la page « Nouvelle tâche » et le détail d'un agent).

### Piste A retenue, en simple (2026-09-29)

Maquette : `design/prototypes/ux-a.html`. Retours de l'utilisateur : beaucoup trop d'informations, il faut du plus simple.

- **Accueil** : les agents rangés en **En attente**, **Travaillent**, **Terminés** et **Historique** (replié par défaut), avec une petite différence visuelle (contour orange, carte grise, carte en simple trait). Chaque groupe se replie en cliquant son titre. Pour chaque agent : titre, ce qu'il fait à l'instant, Claude / Codex. Pas de barre horizontale.
- **Pas de chat sur l'accueil** : juste un bouton rond noir avec une **flèche vers la droite**, en bas à droite, qui ouvre un **chat pour un nouvel agent** (dossier et modèle à moitié dans le champ).
- **La page d'un agent** : quand il travaille, deux vues (le choix Suivi | Chat est à moitié dans le champ). **Suivi** : propre, la ligne de métro de ses tâches (trait bleu qui avance, halo léger et lent, code en direct) ; les messages qu'on glisse pendant le travail apparaissent **entre les tâches**. **Chat** : l'historique complet, en chat normal (pas de ligne ni de progression), avec les mêmes messages ; la tâche en cours y est une carte qui ramène au suivi. **Quand la tâche est finie, on revient au chat normal** : la tâche devient une carte « Tâche terminée » qui se déplie, et la conversation continue. Un chat qui n'est pas un agent au travail n'a jamais de ligne de progression.
- **Le champ de saisie** : le style « Champ » de la planche des composants (gris en creux, plus contrasté que la bulle de chat), avec le petit micro et la flèche d'envoi à droite. Le texte est centré sur une ligne et grandit jusqu'à 5 lignes, sans flèches de défilement. Les options sont **à moitié dans le champ**, en bas à gauche : **dossier et modèle** (nouvel agent) ou **Suivi | Chat** (agent au travail).
- **Parler** : micro cliqué ou **raccourci clavier maintenu** (proposition : Ctrl + Win, comme Wispr Flow) ; le texte s'écrit dans la bulle. Pas d'étape « parler ou écrire ».
- Thème sombre : gris des cartes un peu plus contrasté (`--well` `#17171A`).

### Référence visuelle

`design/references/boutons-lanceur.png` : on garde **les couleurs** (gris, blanc, noir) et **la forme des boutons** (capsules, boutons ronds, sélecteur à capsule blanche, ombres douces). On ne garde **pas** la mise en page « lecteur » avec un bouton Play.

Couleurs relevées sur l'image :

| Quoi | Couleur |
|---|---|
| Fond | `#F9F8F9` |
| Barre qui contient les boutons | `#F4F3F4`, liseré blanc, ombre douce |
| Rail du sélecteur | `#E8E7E9` |
| Capsule du choix actif | `#FFFFFF` |
| Bouton rond | dégradé `#EFEEF0` → `#E3E2E4` |
| Bouton principal | `#050406` (presque noir), texte blanc |

## 2. Choix de fond (d'accord sur le principe, pas pour le MVP)

- **A. La maison de Mikky** : une grande fenêtre qu'on ouvre depuis l'île, pour les sessions, les tâches et les fichiers. L'île reste le compagnon (état, alertes, feu vert, lanceur rapide). Pour le MVP, tout se passe dans la petite fenêtre à droite.
- **B. `mikkyd` (Rust)** sur le PC et le VPS : il fait tourner les agents en arrière-plan, même app fermée. L'app Flutter n'est qu'un écran branché dessus. À faire quand on aura besoin du VPS ou du téléphone.

## 3. Toutes les fonctionnalités (numérotées pour s'y retrouver)

★ = proposé pour une première version.

**Agents et abonnements**
1. ★ Claude Code avec l'abonnement de l'utilisateur : Mikky lance le `claude` officiel, sur lequel l'utilisateur s'est connecté lui-même. Mikky ne touche jamais au jeton.
2. ★ Codex de la même façon (le `codex` officiel, connecté au compte ChatGPT).
3. ★ Agents en arrière-plan dans un terminal caché, qui continuent quand on ferme la fenêtre.
4. ★ Feu vert et questions depuis l'île. Jamais d'approbation sans clic.
5. Limite d'abonnement : savoir quel agent est bloqué et quand il repart ; Mikky prend son état « limité ».

**Sessions (idées de VelaTerm)**
6. ★ Rangement : projets → groupes → sessions.
7. ★ Où l'agent travaille, au choix à chaque lancement : dossier d'origine, worktree partagé, ou un worktree par session.
8. ★ Deux vues pour une même session : conversation lisible, et le vrai terminal de Claude ou Codex.
9. Reprendre une ancienne session là où elle s'était arrêtée.
10. Agents qui se parlent : chercher dans les autres sessions, poser une question sur l'une d'elles, envoyer un message à une session en cours. Donné aux agents comme un outil MCP (le « canal commun » de l'étape 4).

**Tâches (le meilleur de Paperclip, en simple)**
11. ★ Tableau : À faire · En cours · À vérifier · Fait. Une tâche = consigne, projet, pièces jointes, commentaires.
12. ★ Donner une tâche à un agent ou à une boucle d'un clic ; la tâche garde le lien vers sa session et ses modifs.
13. Sous-tâches et « bloquée par ».
14. Routines : tâches qui se relancent seules (« chaque matin, trie les issues GitHub »).
15. Rôles tout prêts (développeur, relecteur, testeur) : consigne + modèle + droits. Version simple de l'organigramme de Paperclip, qu'on laisse de côté.
16. Journal : qui a fait quoi, quand, sur quelle tâche.

**Fichiers**
17. ★ Arborescence et aperçu (code coloré, images, Markdown).
18. ★ Modifs d'un agent par session ou par tâche : garder ou annuler, fichier par fichier.
19. Petit éditeur pour retoucher un fichier à la main.
20. Glisser un fichier sur l'île : Mikky l'attrape et demande « à quel agent ? ».

**LocalSend**
21. ★ Mikky parle le protocole LocalSend : il apparaît comme un appareil dans l'app LocalSend du téléphone et des autres PC. Réception (une capture du téléphone → à un agent ou dans le projet) et envoi (un fichier fait par un agent → le téléphone).

**VPS et téléphone**
22. ★ Ajouter un VPS : connexion SSH (clé dans le coffre de Windows), installation de `mikkyd`, agents et fichiers du VPS à côté de ceux du PC.
23. Boucles et routines la nuit sur le VPS.
24. App téléphone : suivre, donner son feu vert, lancer. Jumelage par QR code, liaison chiffrée, notification quand un agent attend et qu'on n'est pas au PC.
25. Ouvrir Mikky depuis n'importe quel navigateur avec un lien de jumelage.

**Le compagnon (ce que Paperclip n'a pas)**
26. ★ Raccourci clavier : un champ s'ouvre dans l'île (« lance un agent qui corrige les tests de mikky_engine »).
27. ★ Récap au retour : « 3 tâches finies, 1 bloquée, 1 attend ton feu vert ».
28. Mikky montre la boucle en cours (tour 3/10, tests rouges ou verts) avec ses transformations.

**Mails (ajouté le 2026-09-29)**
37. Classer les mails en local avec un petit modèle (MVP, voir §1). Plus tard : résumés, brouillons de réponse, règles, étiquettes appliquées dans la boîte.

**Mikky, un mini-téléphone (ajouté le 2026-09-29)**
38. **Mikky comme un petit téléphone** : de base, on suit les agents ; mais on peut ouvrir des **mini-apps** : une app Messages pour répondre aux mails et aux messages, une app pour orchestrer des agents (les boucles), une app Partage (LocalSend), etc.
39. **Communauté et plugins** : chacun peut créer et partager une mini-app, et on installe ce qu'on veut (comme les plugins de Paperclip, mais sous forme d'apps).
40. **Demander à Mikky d'ouvrir une app** (« ouvre mes mails », « lance l'orchestrateur ») : plus tard, pour que Mikky soit un peu agentique, en restant simple.

## 4. Les boucles agentiques (« modes de travail »)

Garde-fous communs : nombre de tours et temps maximum, arrêt près de la limite d'abonnement, pauses pour demander l'avis de l'utilisateur, bouton « tout arrêter », réglage « combien d'agents en même temps » (plusieurs agents sur un abonnement atteignent vite la limite).

29. ★ **Jusqu'au vert** : l'agent recommence jusqu'à ce qu'une commande de vérification passe (tests, build, lint).
30. ★ **Chef et équipe** : un planificateur découpe, l'utilisateur valide le découpage, des exécutants travaillent en parallèle (un worktree chacun), un vérificateur relit, on fusionne. Ce qui ne passe pas revient à la même session, avec son contexte.
31. ★ **Codeur et relecteur** : l'un code, l'autre relit, jusqu'à « approuvé ». Idéal : Claude code et Codex relit (deux modèles ne ratent pas les mêmes erreurs).
32. **Ralph** : la même consigne relancée avec une mémoire neuve à chaque tour, et un fichier de plan coché au fur et à mesure.
33. **Tournoi** : 2 ou 3 essais en parallèle (deux Claude et un Codex, par exemple) ; un juge compare (tests + relecture) et garde le meilleur.
34. **Casseur et réparateur** : l'un écrit des tests qui cassent le code, l'autre répare.
35. **Chercher → Planifier → Coder → Vérifier** : quatre étapes, avec le feu vert de l'utilisateur entre chacune.
36. **Modes perso** : enregistrer un enchaînement comme recette réutilisable.

## 5. Ordre proposé après le MVP

- Sessions et worktrees, les deux vues, feu vert depuis l'île, la maison de Mikky (1-4, 6-8, 26).
- Tâches, fichiers et modifs, les 3 premières boucles, récap (11-12, 17-18, 27-31).
- VPS, téléphone, agents qui se parlent, routines, les autres boucles (10, 14, 22-25, 32-36).

## 6. Notes techniques à garder

- **Décisions du 2026-09-29 (fin de session)** : raccourci **Ctrl + Win maintenus** pour parler (validé) ; **Whisper en local plus tard** ; les agents se lancent **sous Windows ou dans WSL**, au choix ; l'app doit aussi **marcher sous Linux** ; permissions **Demander** (par défaut) ou **Auto**, au choix à chaque lancement.

- Sur le PC (2026-09-29) : `codex` 0.153.4 est installé (npm) ; `claude` n'est pas dans le PATH (seulement celui de l'extension VS Code). Il faudra installer Claude Code en ligne de commande pour que Mikky le lance.
- LocalSend utilise le port 53317 (découverte en multicast `224.0.0.167`, transfert en HTTPS). Si l'app LocalSend tourne aussi sur le même PC, conflit de port : Mikky devra en prendre un autre (le port est annoncé à la découverte).
- Mails : tout reste sur le PC (règle « pas de télémétrie »). Identifiants dans le coffre de Windows.
- Garder le 0 % de CPU île cachée : LocalSend et les mails doivent attendre des événements, sans boucle d'interrogation ; le modèle n'est chargé que pendant qu'il classe.

## 7. Ce qu’on avait oublié (2026-09-29, retours de l'utilisateur et comparaison avec Paperclip)

Après le premier essai de la petite fenêtre. ✔ = fait. Rien d'autre n'est décidé : on choisit dans cette liste.

**Retours de l'utilisateur**
41. ✔ Copier-coller : Ctrl+C / Ctrl+V dans le champ, texte du chat sélectionnable, menu « Copier » au clic droit.
42. **Ranger les sessions** : renommer, épingler, **archiver** (cachée de l'accueil, retrouvable dans « Archives », réversible), **supprimer** (oublier dans Mikky ; en option, effacer aussi le fichier de session de Claude / Codex, avec confirmation), marquer une erreur comme **réglée**.
43. **Sessions reprises** : une session reprise (« fork » de Claude, `resume` de Codex) recopie l'historique de l'originale, avec les mêmes identifiants de messages. Mikky peut donc les relier : une seule carte (la plus récente), l'originale repliée dedans, et son erreur n'est plus « En attente ». Cas vu : « Mikky app reprise » (erreur de connexion) reprise dans « Mikky app reprise (fork) ».
44. **Erreurs qui traînent** : une erreur sans nouvelle depuis un moment (30 min ?) passe dans « Terminés », avec un point rouge, au lieu de rester « En attente ».
45. **Logos** des outils sur les cartes, les pages et le menu du modèle : Claude, Codex, et ceux qu'on ajoutera. Paperclip utilise les icônes de Lobe (licence MIT) : Claude, OpenAI, pi, OpenCode, Gemini, Cursor, Grok, Kimi, Hermes, OpenClaw.
46. **Plus d'outils** que Claude et Codex, comme Paperclip : **OpenCode** (parle ACP lui-même : `opencode acp`), **pi**, **OpenClaw**, **Gemini CLI** (ACP aussi), Cursor, Kimi, Grok, Hermes. Même principe : l'outil officiel, déjà connecté par l'utilisateur.

**Ce que Paperclip a et que Mikky n'a pas encore** (en simple, pour une personne)
47. **« Ce qui a besoin de moi »** (leur Inbox / WhatNeedsMe) : une seule liste des questions, feux verts et erreurs de tous les agents. Chez nous : le groupe « En attente », à rendre accessible d'un raccourci.
48. **« Toujours autoriser »** : Claude et Codex proposent déjà l'option (`allow_always`) ; Mikky n'offre que Oui / Non. À ajouter, en restant par lancement.
49. **Questions à choix** de Claude (son outil de question) : afficher les choix au lieu d'un Oui / Non.
50. **Coûts et limites** (leur page Costs) : jetons utilisés par session, et la limite de l'abonnement (combien il reste, quand ça repart). Les adaptateurs envoient déjà l'usage (`usage_update`).
51. **Artefacts** : les fichiers produits ou modifiés par une tâche, en un endroit, avec le diff complet et « Garder / Annuler » (idée 18).
52. **Recherche** dans toutes les sessions (leur Search).
53. **Journal** (leur Timeline) : qui a fait quoi, quand.
54. **Projets** : ranger les sessions par dossier ou projet (idée 6).
55. **Routines** (planifier, partie B du MVP) et **heartbeats** (un agent qui se réveille à heure fixe pour vérifier son travail).
56. **Passer la main** (leur handoff) : donner le travail d'un agent à un autre (« Codex, relis ce que Claude a fait »), avec le contexte.
57. **Consignes et compétences par agent** (leur Skill Studio, AGENTS.md / CLAUDE.md) et **serveurs MCP** : voir et choisir ce que l'agent a sous la main.
58. **Espaces de travail** : worktree par session, ports des serveurs lancés par l'agent (idée 7).

**Dans le chat**
59. Joindre un fichier ou une image (glisser-déposer, coller une capture), mentionner un fichier avec @.
60. Les commandes de l'agent (`/plan`, `/compact`…), que les adaptateurs annoncent déjà.
61. Blocs de code avec bouton « Copier », liens cliquables, Markdown complet.
62. Modifier ou renvoyer son dernier message ; arrêter pendant qu'il écrit.
63. Ouvrir le dossier, ou le fichier modifié, dans VS Code.

**L'app autour**
64. Notification Windows quand un agent attend ou a fini, et que l'île est cachée.
65. Icône dans la zone de notification, démarrage avec Windows, raccourci global pour ouvrir Mikky (idée 26).
66. Premier lancement guidé : quels outils sont là, lesquels sont connectés, WSL ou pas.
67. Écran de réglages (thème, position, permissions par défaut, outils), au lieu du seul menu du clic droit.

## 8. Inspirations

- Paperclip : https://github.com/paperclipai/paperclip (agents, tickets, heartbeats, budgets, approbations, routines).
- VelaTerm : https://velaterm.com/docs/session-commands (sessions, worktrees, `vsearch` / `vrefer` / `vtell`, planifier / exécuter).
- Protocole LocalSend : https://github.com/localsend/protocol
