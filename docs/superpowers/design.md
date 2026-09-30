# Mikky — le design

Dernière mise à jour : 2026-09-30

Tout ce qui est décidé sur l'apparence de Mikky : direction artistique, marque, couleurs, pixels, écrans, mouvement, et ce qui a été écarté. La construction de l'app (code, agents, ce qui marche, pièges) est dans `reprise.md`. Quand on touche au visuel, on lit ce fichier ; quand une décision de design est prise, on l'écrit ici.

## 1. Comment on travaille le design

- **La référence, ce sont les planches** : `mikky.exe --kit` (code : `app/lib/boards/`). Comme Figma : planches Marque, Composants, Accueil, Agent, Messages ; chaque écran dans chacun de ses états, vivant (ça bouge, ça se clique), à partir de fausses sessions (`fake_sessions.dart`). Clair, sombre ou les deux. Glisser pour se déplacer (partout, Espace + glisser, bouton du milieu), molette pour défiler, Maj de côté, Ctrl pour zoomer.
- **On propose, l'utilisateur choisit** : plusieurs variantes côte à côte sur une planche, il dit laquelle garder (souvent en quelques mots), on retire les autres. Un composant n'apparaît qu'une fois sur la planche Composants (pas de doublons).
- **Réglages en direct** : quand une valeur se juge à l'œil, des curseurs dans la colonne de gauche des planches ; l'utilisateur envoie ses valeurs (« Copier »), on les met dans l'app, puis on retire les curseurs (fait pour le flou du haut).
- **Vérifier avant de montrer** : images de test des planches (`app/test/boards_test.dart`, `test/goldens/boards/`), les regarder, corriger, puis relancer `--kit`.
- Les maquettes HTML de `design/prototypes/` sont **dépassées** depuis le 2026-09-30 (abandonnées par l'utilisateur) ; gardées pour l'historique.

## 2. Direction artistique

### Planche technique (2026-09-30)

Page « Technique » dans `--kit`, sur le même canvas avec zoom et thèmes clair/sombre. Présentation à plat : schéma des trois couches, parcours cliquable d’une demande, transition Dart/Rust, optimisations, mesures, données et feuille de route R2–R7. Statuts toujours écrits en plus de la couleur : vert « En place », orange « Transition », violet « Prévu », bleu « À mesurer ». Le contenu est un instantané documenté, pas une télémétrie ; les anciens benchmarks sont datés et les capacités futures explicitement distinguées du code actuel.

**« Mikky, le chat magique, avec de l'informatique et des pixels »** (2026-09-30).

- Une interface **à plat** : noir, blanc, gris ; pas de cartes en relief, pas de blocs ; des lignes simples, des pilules, des boutons ronds.
- Les **indicateurs sont en pixel art** : de petits feux d'artifice de pixels carrés, un peu espacés, sans fond ; quelques couleurs franches, pas de dégradé lissé.
- **Mikky reste dessiné en courbes** (le vrai dessin, noir, grands yeux blancs) ; la marque, elle, est en pixels.
- Moderne et doux : survol partout, flous progressifs, verre dépoli là où le contenu passe dessous.

## 3. Marque

- **Nom** : Mikky (validé).
- **Logo** : **Mikky lui-même**, la mascotte bien présente. Retenue : **C, Mikky qui dépasse du bas du carré** (« de loin la mieux »). Restent à côté : **C2** plus près (juste les oreilles et les yeux), **C3** penché par le coin, **C4** par le côté. **À ajouter plus tard : un petit quelque chose de magique.** Ensuite : l'icône de l'app et de la zone de notification. Sur blanc et sur gris anthracite `#2A2A2E` (sur noir, un chat noir disparaît).
- **Nom de l'app en lettres** : police pixel **Jacquard 24** (préférée), puis **Jersey 10** (`app/assets/fonts/trial/`).
- **Texte** : **Geist** et **Geist Mono** partout (choisies).
- **Couleurs signature** (validées, **gardées pour plus tard**) :
  - orange, de la capture de l'utilisateur : `#FF8204` `#FA500F` `#E51300` `#C4001D` ;
  - le même en bleu (mêmes teintes, mêmes écarts) : `#04BCFF` `#0F84FA` `#0045E5` `#000DC4`.
  - Code : `PixelFxPalette.signatureOrange` / `signatureBlue`.
- **Feux d'artifice signature** (bleu et orange, en essai sur la planche Marque, `SignatureFx`) : pivoine, deux temps, saule, anneau, spirale, crossette, Mikky (les étincelles dessinent sa tête), paillettes, comète, ondes ; et le calme aux deux couleurs, bleu au cœur, orange au bout.

## 4. Couleurs de l'interface

Mêmes noms en clair et en sombre (`app/lib/ui/tokens.dart`, planche Marque) :
- **Fonds** : `board` (bureau), `island` (la fenêtre), `well` (creux, bulles), `track` (pistes, code, champ), `thumb` (curseur, Oui), `hover` (survol), `line` (traits).
- **Encre et texte** : `ink` (bouton principal, tes bulles), `text`, `text2`, `text3`.
- **États** (couleurs d'Apple) : bleu travaille · violet réfléchit, internet · orange attend, commande · vert terminé, crée · rouge erreur, supprime · jaune limité, déplace · gris dort, historique.
- Thème clair : couleurs système d'Apple, pas de lueur, pas de points. Thème sombre : l'île noir « A ».

## 5. Pixels

- **L'état d'un agent** (`StatusFx`, `app/lib/ui/pixel_fx.dart`) : un **feu d'artifice calme** de 7 × 7 pixels, qui passe petite étoile → moyenne → grande → moyenne, sur place, dans la couleur de l'état. Chaque état à son rythme : **attend le plus vite** (1,2 s), travaille 1,6 s, les autres 2,4 s, **dort le plus lent** (4,8 s) ; **terminé figé**.
- **Palettes** (4 niveaux, du cœur au bord) : violet, bleu, orange, rouge, jaune, gris, vert (le vert du thème). En clair, le cœur blanc prend une teinte de la couleur.
- **Petite étoile fixe** (`PixelStar`, 5 × 5) : une par étape de tâche dans le chat, de la couleur de son action — **crée vert, modifie bleu, commande orange, internet violet, supprime rouge, déplace jaune ; lire et chercher gris** ; l'étape en cours bouge (feu d'artifice bleu) ; les étapes à venir en gris pâle.
- **Étoile grise figée** pour les groupes sans agent actif de l'accueil (Historique, Archives), à la place de l'ancien carré gris.
- En essai sur la planche Marque, sans usage : étincelle, feu d'artifice complet, galaxie ; l'étoile qui réfléchit.

## 6. Mikky

- Pas de bouche, pas de pattes, pas de pupilles ; la queue seulement dans certains états, plus tard. **Les oreilles portent l'émotion.**
- **Ses transformations, c'est lui-même** qui se transforme, de façon organique et imparfaite, en gardant sa couleur, ses poils et le plus possible sa forme de base. Changement de forme mou comme de la gelée (ressort 95 / 0,38), toujours en repassant par le chat.

| Quoi | Validé |
|---|---|
| Travaille | **le chat qui saute**, lentement (un saut doux toutes les ~2 s, 1,5 × plus lent qu'avant ; « vraiment plus lentement »), sans badge ; il regarde la souris, même quand l'agent lit ou cherche (plus de balayage du regard) |
| Réfléchit | le chat qui regarde en l'air, avec la bulle « ••• » au-dessus de la tête ; pas de saut |
| Attend ton feu vert | en boucle : 2 sauts en chat → « ! » sans yeux (barre large en haut, fine en bas, point bien séparé) pour 3-4 sauts → chat ; pas de badge |
| Amour | la mascotte **à peine** déformée en cœur, yeux contents, petits cœurs au-dessus des oreilles |
| Terminé | petit saut un peu plus haut, yeux contents, une oreille plus grande, étincelles ; pas de roulade |
| Surpris | grands yeux ronds, oreilles très hautes |

Code : `packages/mikky_engine/lib/src/mikky/`. Tous les états se voient dans l'écran de réglage (`mikky.exe --tuning`).

## 7. Les écrans de la petite fenêtre

### Accueil
- Groupes repliables **En attente / Travaillent / Terminés / Historique** (et Archives) ; en tête de groupe, l'état en feu d'artifice (ou l'étoile grise), le nom, le nombre ; titres alignés avec les lignes.
- **Des lignes, pas de cartes** :
  - au travail, en attente : le **logo de l'outil** (32 px) à gauche, au milieu des deux lignes de texte ; il tourne quand l'agent travaille ou réfléchit, il rebondit quand il attend ;
  - terminés : ligne simple, petit logo (22 px), titre, « il y a 2 min · WSL » à droite ;
  - les logos doivent paraître de la même taille : celui d'OpenAI (Codex) est dessiné à 84 % de son carré, son nœud remplissant tout le carré (`Brand.scale`) ;
  - survol : le carré blanc qui glisse (voir Mouvement).
- **Oui / Non à plat** sous la ligne qui attend : un carré blanc (avec un trait fin) sous la réponse choisie, qui **glisse** vers celle qu'on presse ; Oui choisi par défaut ; la commande en petite pilule à côté.
- Mikky en petit en haut à gauche ; bouton rond noir → en bas à droite pour un nouvel agent.
- Claude au travail : son logo tourne et respire ; **en essai** sur la planche Composants, l'étoile de Claude Code (point, croix, astérisque, étoile, fleur, et retour, en orange), à choisir.
- **Petite étoile grise à droite de chaque ligne** (demande de l'utilisateur, 2026-09-30) : l'étoile en pixels (`MenuStar`, 10 px, un peu pâle, plus nette au survol) ouvre le menu de l'agent (pause, reprendre, arrêter, VS Code, renommer, ranger…) sans ouvrir sa page ; le clic droit sur la ligne fait pareil.
- **Agent en pause** (2026-09-30, proposé sur les planches) : dans « Travaillent », même s'il est en pause depuis longtemps ; étoile grise, « En pause », **Reprendre** à plat sous la ligne (même barre que Oui / Non).

### L'île fermée, à droite
Sous Mikky, le **feu d'artifice de l'état le plus pressant** parmi les agents (attend, erreur, limite, travaille, réfléchit, terminé, dort) ; son nom « Mikky » quand il n'y a pas d'agent.

### Limite de l'abonnement
Un vrai état, **jaune** : sur l'accueil « Limite atteinte · reprend à 17 h 10 » (l'heure lue dans le message de Claude ou de Codex) ; dans le chat, la tâche « Limite atteinte » et une carte jaune « Limite de l'abonnement atteinte · Reprend à 17 h 10 ».

**Ensorcelée** (le mode magique, 2026-09-30) : sur la carte de la limite, « Relancer » tout de suite ou **« Ensorceler »** : Mikky relancera la tâche tout seul une minute après la reprise, par un message à l'agent (« La limite de l'abonnement est levée : reprends la tâche là où tu t'étais arrêté. ») ; heure inconnue : il essaie 30 min plus tard ; si la limite retombe, il attend la reprise suivante. La carte passe en **violet**, la couleur de la magie : « Ensorcelée · Se relance toute seule à 17 h 11 », avec « Annuler ». Sur l'**accueil** aussi : la ligne d'un agent limité porte une **étoile jaune** après son titre, « Limite atteinte · reprend à 17 h 10 », et « Relancer / Ensorceler » ; ensorcelé, une **étoile violette** qui scintille, « Ensorcelé · se relance à 17 h 11 », « Annuler ». Dans la page de l'agent ensorcelé, une **étoile violette en haut au milieu**, entre les boutons. **Relance automatique** (mode global, interrupteur en bas de l'accueil, gardé dans les réglages) : tout agent qui bute sur une limite est ensorcelé tout seul ; jamais une vieille session de l'historique au démarrage. Les sorts eux-mêmes sont en mémoire : un redémarrage de Mikky les lève (le mode global, lui, reste).

### Page d'un agent
- **Pas de titre ni de bandeau** : le fil remplit la page. Les boutons **flottent** dessus : retour à gauche ; à droite **pause** (deux traits, seulement pendant qu'il travaille ; remplace le carré « arrêter » le 2026-09-30, qui n'arrêtait que le tour) et **« ··· »** (menu : mettre en pause ou reprendre, **arrêter l'agent** (fin de son processus et de tout ce qu'il a lancé ; la session reste), ouvrir dans VS Code, ouvrir le dossier, renommer, épingler, archiver, marquer l'erreur comme réglée, supprimer). Le clic droit sur une ligne de l'accueil ouvre le même menu.
- **En pause** : sous le fil, une carte grise « En pause · Travail arrêté, session gardée » avec **Reprendre**, qui dit à l'agent de continuer là où il en était ; écrire un message reprend aussi.
- **Flou en haut** (`TopBlur`) : le fil passe sous les boutons dans un flou progressif avec un voile de la couleur de la fenêtre. Valeurs choisies par l'utilisateur : **hauteur 65 · 3 couches · flou 0,90 · voile 0,38 · rampe 1,05**.
- **Flou en bas, seulement derrière le champ** (pas au-dessus) ; le champ y est en **verre dépoli**.
- Deux vues pendant qu'il travaille : **Suivi** (ligne de métro des tâches, code en direct sous l'étape en cours) et **Chat** ; le choix à moitié dans le champ.

### Le champ de saisie
- **Fin, comme celui du dernier iPhone** : 40 px de haut, pilule, 20 px de marge de chaque côté, bas dans la fenêtre ; micro et flèche d'envoi (noire) à droite, petits ; grandit jusqu'à 5 lignes.
- Ses options **à moitié dedans**, en bas à gauche : Suivi | Chat, ou dossier et modèle pour un nouvel agent. Avec des options, le champ prend 8 px de plus en bas (48 px) pour qu'elles ne touchent pas le texte.

### Le chat
- **Tes messages** : bulles noires (blanches en sombre) à droite. **Les réponses de l'agent** : sans bulle, **sur toute la largeur**.
- **Listes** : puces et numéros en retrait, sous-listes, éléments rapprochés, pas de saut de ligne quand un élément continue.
- **Une tâche fait partie de la page** (pas de carte) : son état en pixels, son titre, ses chiffres (étapes, fichiers, durée). Ouverte : **les grandes lignes** en points d'étape (le plan de l'agent, ou ses outils regroupés : « Lit 3 fichiers », « Crée usage_test.dart », « Lance une commande »…) ; un clic sur une étape montre ses outils (commande ou fichier en mono ; un clic montre la sortie ou le code) ; « Voir le détail » montre tout (réflexions en gris clair, messages en cours de route). La dernière tâche ouverte, les anciennes repliées.

### Nouvel agent
Mikky au milieu, « Qu'est-ce qu'on lance ? », le champ avec le dossier et le modèle dessous.

## 8. Mouvement

- **Ressorts** : sélecteurs 380 / 0,70 (un peu gluants) ; formes de Mikky 95 / 0,38 (gelée). Rien de trop gluant : l'utilisateur veut que ce soit satisfaisant, pas mou.
- Boucles décoratives à **30 images par seconde**, sur une seule horloge ; **figées** quand Windows demande moins d'animations ; **0 % de CPU** île cachée.
- **Survol de base : le carré blanc de Oui / Non** (blanc, trait fin, ombre douce) qui **glisse** sur un ressort (380 / 0,70) jusqu'à la ligne sous la souris, et revient **se poser sur la ligne choisie** (`SlidingHover`, `HoverTarget` ; choisi par l'utilisateur le 2026-09-30). Dans une liste sans choix (lignes de l'accueil, étapes et outils du chat), il suit la souris. **Quand il marque un choix** (colonne des planches, et demain les onglets, menus…), **il reste sur le choix** et ne glisse qu'au clic ; le survol, c'est **le nom qui s'éclaire** : gris clair au repos (`text3`), noir sous la souris. **Contraste voulu** (capture de l'utilisateur) : carré blanc sur **fond gris clair** (`well`, ~`#F5F5F5`), ombre douce, sans trait fin ; le trait fin seulement pour un carré blanc sur la fenêtre blanche. Ailleurs (puces du champ, options des sélecteurs), un survol simple. Le mouvement du carré est le même dans les deux sens et pour toutes les distances ; rien de lourd ne doit se construire pendant qu'il glisse (dans les planches, la nouvelle planche s'affiche une fois le carré arrivé, 0,22 s).

## 9. Écarté (ne pas reproposer)

- Pour les états : le liseré vert autour des logos, la matrice de points qui s'illumine, le « snake » / lanceur carré, les carrés d'état 3 × 3, les reflets façon diamant, l'effet qui tourne, l'éclat final du feu d'artifice.
- Oui / Non en relief ; la carte grise « en attente » ; l'animation de clic trop gluante.
- Mikky en boule de poils pour « travaille » ; l'étoile magique sur Mikky pour « réfléchit ».
- Logo : l'étoile pixel bleue et orange ; Mikky entier, la tête en grand, la tête en pixels ; C5 à C9 (tête en bas, content, en pixels, sur bleu, sur orange).
- Polices de texte autres que Geist (Inter, Host Grotesk, Hanken, Schibsted, Onest, Space Grotesk) ; pour le nom : Tiny5, Silkscreen, Jersey 15 à 25, Workbench, Jacquard 12, Micro 5, Press Start 2P, Doto, etc.
- Les maquettes HTML comme référence.

## 10. Reste à décider

1. **Logo** : le petit quelque chose de magique ; puis l'icône de l'app et de la zone de notification.
2. **Couleurs signature** : où elles servent dans l'interface (plus tard).
3. **Palettes pixel** : les figer et les nommer.
4. **Typographie** : une échelle nommée (titre, corps, légende, code).
5. **Mikky en pixels** ? (première tête dans le feu d'artifice « Mikky »).
6. **Menus à nos couleurs** : le choix de l'agent, du modèle et du dossier passe encore par le menu natif de Windows.
7. **Infobulles** à nous (bulle blanche, ombre douce).
8. **Sons** : un petit bip pixel quand un agent attend ou finit ?
9. **Écrans à dessiner** : connexion à Claude / Codex, réglages ; une boîte de confirmation, une notification d'erreur, un état vide.

## 11. Où c'est dans le code

- Jetons (couleurs, texte) : `app/lib/ui/tokens.dart` · pixels : `app/lib/ui/pixel_fx.dart` · composants : `app/lib/ui/` · fenêtre : `app/lib/side/` · Mikky : `packages/mikky_engine/lib/src/mikky/` et `app/lib/mikky/mikky_painter.dart`.
- Planches : `app/lib/boards/` (`board_brand.dart`, `board_components.dart`, `board_screens.dart`, `canvas.dart`, `boards_app.dart`, `fake_sessions.dart`).
