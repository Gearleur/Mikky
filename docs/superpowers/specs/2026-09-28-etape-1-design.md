# Mikky — Étape 1 : Mikky et l'île sur Windows

Date : 2026-09-28 · Statut : validée par l'utilisateur

## 1. Contexte et intention

Mikky est une petite mascotte (un chat noir aux grands yeux) qui vit dans une « île » en haut de l'écran, inspirée de l'app macOS Coucou (Mochi dans le notch). À terme, Mikky servira à suivre et piloter des agents Claude Code sur le PC, puis sur le téléphone, puis sur un VPS où les agents se parlent sur un canal commun.

Feuille de route décidée :
1. **Étape 1 (cette spec)** : Mikky et l'île sur Windows, avec de faux agents (mode démo).
2. Étape 2 : brancher les vrais agents Claude Code sur le PC (hooks, approbations, questions, sessions lancées par l'app).
3. Étape 3 : l'app mobile (même code Flutter).
4. Étape 4 : `mikkyd`, un démon en Rust sur le PC et le VPS, qui gère les agents et le canal où ils se parlent.

**But de l'étape 1** : avoir sur Windows une île et un Mikky aussi fluides et soignés que les prototypes validés, en consommant très peu, pour poser des bases saines avant de brancher les agents.

**C'est réussi quand** :
- côte à côte avec les prototypes de `design/prototypes/`, on ne voit pas de différence sur la silhouette, les yeux, les ressorts, la goutte, la bulle séparée, les points et les deux thèmes ;
- tous les états et émotes se déclenchent depuis le menu démo ;
- l'île ne gêne jamais : les clics passent à travers partout hors de l'île ;
- île cachée : 0 % de CPU ; île compacte : moins de 3 % ; mémoire : moins de 150 Mo.

## 2. Hors périmètre de l'étape 1

Vrais agents et hooks Claude Code, chat et champ de saisie, sons, glisser-déposer de fichiers, queue de Mikky, Liquid Glass, emplacements « gauche » et « bas droite » (« à droite » est fait, voir §3), macOS, mobile, `mikkyd`.

## 3. Décisions déjà prises (brainstorming du 2026-09-28)

### Technique
- **Flutter partout** (desktop maintenant, mobile ensuite). Rust est réservé à `mikkyd` (étape 4).
- Windows seulement pour l'étape 1. Le repo vit sur Windows, dans `C:\Users\alexa\projet\mikky` (déplacé hors de WSL le 2026-09-28, voir §11).

### Mikky (voir `design/prototypes/mascotte-variantes.html`, carte « S · Touffes + queue » sans la queue)
- Corps noir `#0C0C0E`. Silhouette « G » : superellipse d'exposant 2,4, rx = 1,06 R, ry = 0,92 R, élargie en bas (facteur 0,055). Les oreilles sont des bosses du même contour (centre à ±0,60 rx, demi-largeur extérieure 0,40 rx, intérieure 0,44 rx, hauteur 0,55 R, courbure 0,85), pas des formes séparées.
- Touffes : petite touffe au sommet et joues duveteuses (ondulation du contour, animée lentement).
- Yeux : grands ovales blancs `#F7F7F7`, **sans pupille**, largeur 0,21 R, hauteur 0,50 R × 1,25, écart angulaire ±0,30 rad, hauteur 0,26 rad sur la sphère. Pas de bouche, pas de pattes.
- Technique d'animation reprise de Mochi (`BotEngine.swift` dans Coucou) : yeux projetés sur une sphère (yaw, pitch, roll), tweens à keyframes avec easings, lissage exponentiel indépendant du framerate, ressorts, clignements aléatoires (2,2 à 5,4 s, double clignement 22 %), respiration, regard qui suit la souris (`tanh(dx/260)`, `tanh(dy/200)`), tête qui penche du côté où il regarde, mouvements d'oreilles aléatoires.
- Sur fond noir, un liseré clair `rgba(255,255,255,.22)` détache Mikky de l'île.

### L'île (voir `design/prototypes/ile-noir-et-blanc.html`)
- Dessinée par un **fragment shader** (SDF) : rectangle à coins continus (norme puissance 4, « squircle »), fusion par *smooth-min* avec la goutte de notification et la bulle séparée, ombre en deux couches.
- Ressorts : île « sèche » (raideur 210, amortissement 0,74) ; goutte « gluante » (raideur 120, amortissement 0,42) ; bulle séparée (150, 0,5). À l'ouverture, la hauteur suit la largeur avec 45 ms de retard.
- Tailles : fermée 186 × 36 (rayon 18) ; ouverte « Focus » 430 × 178, « Liste » 450 × 180 (rayon 30). L'île est collée au bord haut de l'écran, centrée (le haut dépasse de l'écran, seuls les coins bas sont visibles).
- **Thème noir « A »** (par défaut) : fond `#070708`, liseré intérieur de 1,3 px, police Geist et Geist Mono, touches N/Y affichées. **Points vivants** : grille de points autour de Mikky, avec une onde de la couleur de l'agent qui part de Mikky, **seulement en noir et seulement quand un agent travaille**.
- **Thème blanc « pur »** : blanc opaque, trait d'un demi-point, ombre très douce, couleurs système Apple (`#007AFF`, `#FF9500`, `#34C759`, `#FF3B30`, `#AF52DE`), textes label / secondaryLabel, ni halo, ni points, ni touches.
- Le thème suit le réglage clair/sombre de Windows, avec un choix manuel possible.
- **Disposition « Focus »** (par défaut) : l'agent qui a besoin de toi en grand (nom, verbe, commande en mono dans un bloc, actions), les autres en pastilles. **Disposition « Liste »** : une ligne par agent avec barre de progression.
- **Bulle séparée** façon Dynamic Island : île fermée, quand un agent attend (approbation, question, erreur), une bulle ronde sort par la droite avec un point de la couleur d'état, et Mikky la regarde.
- **Goutte de notification** : une goutte se détache par le bas, reste accrochée par un pont de matière, puis se recolle ; Mikky la suit des yeux.
- **Position « à droite »** (ajoutée à la demande de l'utilisateur le 2026-09-28) : en plus de « en haut », l'île peut vivre collée au bord droit de l'écran principal, centrée verticalement dans la zone de travail, **en hauteur comme un téléphone en portrait**. Compacte : onglet 64 × 92 (rayon 22) avec Mikky et « Mikky » dessous. Ouverte : carte 320 × 560 (rayon 38), Mikky en grand en haut, puis le contenu empilé comme une app mobile, textes à l'horizontale. On choisit « en haut » ou « à droite » dans le menu ; le choix est gardé.

## 4. Architecture

```
mikky/
├── packages/mikky_engine/     # Dart pur, sans Flutter : toute la logique, testable
│   ├── mikky/                 #   états, émotes, tweens, ressorts, regard → géométrie de Mikky
│   ├── island/                #   machine à états de l'île (modes, vues, file d'alertes, minuteries)
│   └── agents/                #   modèle d'agent + source de données (démo maintenant, vrais agents à l'étape 2)
├── app/                       # l'application Flutter Windows
│   ├── lib/overlay/           #   fenêtre transparente, clics traversants, suivi de la souris
│   ├── lib/island/            #   widget de l'île : shader + contenu (Focus, Liste, pastille fermée)
│   ├── lib/mikky/             #   CustomPainter qui dessine la géométrie de Mikky
│   ├── lib/demo/              #   faux agents et scénarios
│   ├── lib/tray/              #   icône de la zone de notification + menu
│   ├── shaders/island.frag    #   le shader de l'île (GLSL Flutter)
│   └── windows/runner/        #   code natif C++ pour ce que Flutter ne sait pas faire (voir 5.1)
├── design/prototypes/         # prototypes HTML validés = référence visuelle
└── docs/superpowers/specs/    # specs
```

**Principe** : `mikky_engine` ne dessine rien et ne dépend pas de Flutter. Il reçoit du temps (`dt`), des entrées (souris, clics, événements d'agents) et produit un **instantané** : géométrie de Mikky (contour, yeux, badge, particules), géométrie de l'île (largeur, hauteur, rayon, goutte, bulle), vue et contenu à afficher. L'app ne fait que dessiner cet instantané. Avantages : on teste toute la logique sans écran, et le même moteur servira tel quel sur mobile.

## 5. Composants

### 5.1 Overlay Windows (`app/lib/overlay`, `windows/runner`)
- Une fenêtre sans bordure, **transparente**, toujours au premier plan, absente de la barre des tâches et d'Alt+Tab, placée en haut au centre de l'écran principal. Elle a une taille fixe, suffisante pour l'île ouverte, la goutte et les ombres (environ 560 × 320 px logiques), pour ne jamais redimensionner la fenêtre pendant une animation.
- **Clics traversants** : la fenêtre ignore les clics partout, sauf sur la forme de l'île. Le moteur fournit le rectangle de l'île à chaque changement ; l'overlay active ou coupe la traversée selon la position du curseur.
- **Suivi de la souris hors de la fenêtre** (le regard de Mikky, l'arrivée du curseur dans la zone du haut, la détection d'absence) : par un **hook souris bas niveau Windows** (`WH_MOUSE_LL`), déclenché par les événements, sans boucle d'interrogation, pour rester à 0 % quand rien ne bouge. Les mouvements sont regroupés à 60 Hz maximum avant d'être envoyés à Dart.
- Écran haute densité (mise à l'échelle Windows) et changement d'écran principal gérés.
- Ce composant est le plus risqué : il passe en premier (jalon J0).

### 5.2 Moteur de Mikky (`mikky_engine/mikky`)
Port de `BotEngine.swift` adapté à Mikky (pas de bouche, pas de mains ; des oreilles expressives à la place).

États (repris de Mochi) et leur expression chez Mikky :

| État | Yeux | Oreilles | Geste / extra | Badge |
|---|---|---|---|---|
| idle | ovales | normales, mouvements aléatoires | respiration | — |
| working | ovales | normales | points vivants (thème noir) | « ••• » bleu |
| thinking | ovales | normales | regarde en haut à droite | « ••• » violet |
| searching | ovales | normales | yeux qui balaient | « ••• » indigo |
| approval | grands | dressées | petits sauts | « ! » ambre |
| question | ovales | une oreille pliée | tête penchée | « ? » cyan |
| error | plats | rabattues | secousse à l'entrée | point rouge |
| finished | arcs contents | dressées puis normales | roulade + étincelles | point vert |
| ratelimit | fatigués | tombantes | gouttes de sueur | point orange |
| sleeping | fermés | tombantes | respiration + « z » | — |
| dizzy | spirales | qui tournent | double roulade | — |

Émotes : amour (yeux cœurs, cœurs qui montent), surpris (yeux agrandis, oreilles dressées, saut), fier (yeux étoiles, étoiles), clin d'œil, bâille, content (arcs, petit saut), agacé (fentes, oreilles rabattues).

Interactions : survol (clignement, yeux ×1,08), immobile 1,9 s → amour, clic = « boop » (écrasement), 3 clics en moins de 1,7 s → sonné.

**Transformations (demande de l'utilisateur, 2026-09-29)** : plutôt qu'un badge ou un symbole posé à côté, c'est **Mikky lui-même qui se transforme**, de façon organique et imparfaite, en gardant sa couleur et ses poils : amour → un cœur un peu déformé ; travaille → la boule de poils : **la mascotte elle-même sans ses oreilles**, ses poils de base (ceux de la touffe et des joues) ressortant un peu plus, tout autour du corps, sans secousse ; réfléchit (l'attente) → la même boule de poils qui sautille ; dans les deux cas il reprend sa forme de chat de temps en temps (boule 6 à 9 s puis chat 2,5 à 4 s pour « travaille », boule 4 à 6 s puis chat 2 à 3 s pour « réfléchit ») ; attend ton feu vert → en boucle : deux petits sauts en chat, puis il devient un « ! » sans yeux (barre large en haut, fine en bas, point bien séparé) pour 3 ou 4 sauts, puis redevient le chat. Terminé : pas de roulade, un petit saut un peu plus haut, yeux contents, une oreille plus grande. Surpris : grands yeux ronds, oreilles très hautes. Le passage d'une forme à l'autre est mou, comme de la gelée, et repasse par le chat. Les autres états gardent pour l'instant la silhouette du chat et leur badge ; d'autres transformations (« ? » pour la question…) pourront suivre.

Les formes d'oreilles par état et les émotes n'ont pas été validées visuellement : elles seront réglées dans l'écran de réglage (5.6) et validées par l'utilisateur avant d'être figées.

### 5.3 Machine à états de l'île (`mikky_engine/island`)
Règles reprises de Coucou (`docs/SPEC.md` §3), adaptées :
1. Aucun agent → **cachée** (invisible, 0 % de CPU).
2. Curseur qui arrive en haut au centre alors que l'île est cachée → **aperçu** (petite pastille, Mikky sort, cligne et remue les oreilles) ; s'il reste 650 ms → **ouverte**.
3. Des agents tournent → **compacte** (pastille fermée avec Mikky et un indicateur à droite : anneau de progression, coche ou nombre).
4. Survol en compacte → ouverte après 200 ms ; clic → ouverte tout de suite.
5. Fermeture automatique après 60 s sans activité, avec un trait de compte à rebours pendant les 10 dernières secondes ; Échap ferme.
6. Utilisateur absent (aucun mouvement depuis 3 min) → cachée, même avec des agents ; retour au premier mouvement.
7. Alerte (approbation, question, erreur) → bulle séparée en compacte, et l'île s'ouvre seule sur l'alerte, même en cas d'absence. Elle reste ouverte jusqu'à la réponse.
8. Terminé → ouverte sur « terminé » pendant 5,2 s, puis retrait de l'agent.
9. Plusieurs alertes → file d'attente, une à la fois, dans l'ordre d'arrivée.
10. Mikky (le grand) représente l'agent en focus (la dernière alerte, sinon le premier qui travaille).

Les minuteries utilisent une horloge injectable, pour être testées sans attendre.

### 5.4 Rendu de l'île (`app/lib/island`, `shaders/island.frag`)
- Le shader des prototypes est porté en GLSL Flutter (`FragmentProgram`), avec les uniformes : taille, rectangle de l'île, rayon, goutte, bulle, thème, temps, couleur d'état, points, centre de Mikky, facteur d'échelle.
- Le contenu (textes, boutons, pastilles, blocs de code) est fait en widgets Flutter, par-dessus le shader. Il apparaît avec un fondu, un léger flou et un décalage, après que l'île a commencé à s'agrandir (comme dans les prototypes).
- Polices Geist et Geist Mono intégrées à l'app (licence OFL).

### 5.5 Mode démo et zone de notification (`app/lib/demo`, `app/lib/tray`)
- Icône de Mikky dans la zone de notification. Menu : ouvrir l'île, thème (auto / noir / blanc), disposition (Focus / Liste), Démo ▸ (ajouter un faux agent, forcer chaque état, chaque émote, notification, alerte, lancer le scénario complet), Réglage de Mikky…, Quitter.
- Le scénario démo enchaîne sans intervention : 3 agents qui travaillent, une approbation, une erreur, un « terminé », une notification.
- Les réglages (thème, disposition) sont gardés entre deux lancements.

### 5.6 Écran de réglage de Mikky (outil de développement)
Une fenêtre normale (pas l'overlay), comme les prototypes : Mikky en grand, boutons pour chaque état et émote, curseurs pour les paramètres (hauteur et taille des yeux, largeur du bas, oreilles, ressorts). Elle sert à régler et valider les expressions (5.2) avec l'utilisateur. Accessible depuis le menu, uniquement en build de développement.

## 6. Flux de données

```
hook souris Windows ─┐
clics / survol ──────┼─► mikky_engine (dt, entrées) ──► instantané ──► overlay (zone cliquable)
source d'agents ─────┘        (démo à l'étape 1)                 └──► shader île + widgets + Mikky
```

À chaque frame affichée : l'app transmet `dt` au moteur, récupère l'instantané, dessine. Quand l'île est cachée, **aucune frame n'est demandée** : pas de Ticker actif, seul le hook souris (par événements) peut réveiller l'app.

## 7. Performance
- Cachée : aucun Ticker, aucune frame, aucun timer périodique → 0 % de CPU.
- Compacte : 60 fps tant que Mikky s'anime ; objectif < 3 % de CPU.
- Le contour de Mikky (360 points) est recalculé à chaque frame dans le moteur ; si le profilage le montre coûteux, on passe à 180 points pour la version compacte.
- Mesure : Gestionnaire des tâches et Flutter DevTools, notée dans le README à chaque jalon.

## 8. Erreurs et cas limites
- Le shader ne compile pas (pilote graphique) : l'île se dessine avec un simple rectangle arrondi Flutter, sans goutte fusionnée ; l'app reste utilisable et l'erreur est écrite dans le journal.
- Le hook souris ne s'installe pas : l'île reste utilisable au clic et au survol de la fenêtre ; le regard de Mikky ne suit plus la souris hors de la fenêtre.
- Changement d'écran ou de mise à l'échelle pendant que l'app tourne : la fenêtre se replace.
- Pas d'écran principal détecté : on utilise le premier écran.

## 9. Tests
- `mikky_engine` : tests unitaires (tweens et easings, ressorts, lissage indépendant du framerate, enchaînements d'états, règles 1 à 10 de l'île avec une horloge simulée, file d'alertes).
- Rendu : tests « golden » Flutter (images de référence) de Mikky dans chaque état et de l'île dans chaque vue et thème, avec un temps figé.
- Contrôle visuel manuel : comparaison côte à côte avec `design/prototypes/`, à chaque jalon.
- Performance : mesure du CPU caché / compact et de la mémoire, à chaque jalon.

## 10. Jalons
Chaque jalon se termine par un build, une vérification visuelle et un commit.
- **J0 · Overlay** : fenêtre transparente toujours au premier plan, clics traversants hors d'un rectangle, hook souris, 0 % de CPU caché. C'est le jalon qui valide la faisabilité ; s'il échoue, on revoit l'approche avant d'aller plus loin.
- **J1 · Moteur** : `mikky_engine` (Mikky + île + agents démo) avec ses tests.
- **J2 · Mikky** : painter, états, émotes, interactions, écran de réglage.
- **J3 · Île** : shader, modes, ressorts, goutte, bulle séparée, points, deux thèmes.
- **J4 · Contenu** : vues Focus et Liste, pastille fermée, alerte, terminé.
- **J5 · Démo et finition** : zone de notification, scénario démo, réglages persistés, mesures de performance.

## 11. Environnement de développement
- Flutter 3.47.5 est installé sous Windows (`C:\dev\flutter`), avec Visual Studio 2022 Community (charge de travail « Développement Desktop en C++ ») et le SDK Android.
- Le code vit sur Windows (`C:\Users\alexa\projet\mikky`), pour éviter les problèmes de Flutter avec les chemins réseau `\\wsl.localhost\...` (liens symboliques des plugins, CMake, lenteur).
- Tout passe par le Flutter de Windows : build, lancement, tests, y compris ceux de `mikky_engine`. Le Flutter de WSL ne doit pas toucher ce repo (conflits dans `.dart_tool`).

## 12. Questions ouvertes
- Mini-Mikky par agent : les pastilles gardent-elles un simple point de couleur (validé), ou un mini-Mikky teinté de la couleur de l'agent comme les mini-Mochi de Coucou ? À trancher visuellement au J4.
- Emplacements « gauche » et « bas droite » : repoussés après l'étape 1, mais le moteur calcule l'île à partir d'un point d'ancrage pour ne pas les bloquer.
- Sons de Mikky : à créer (ceux de Coucou sont protégés).
