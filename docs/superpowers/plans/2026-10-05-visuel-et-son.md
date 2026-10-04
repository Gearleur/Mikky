# Plan du 2026-10-05 : le visuel et le son, ensemble

Écrit le 2026-10-04 au soir. Le 4, on a fait **le fonctionnel seulement** (commits `f72b4dd` à `ffd9ad5`) : Mikky réagit à chaque agent, il apporte les demandes avec leur contexte, il y a des sons et des raccourcis, et les hooks de Claude Code et de Codex. Tout ce qui se voit ou s'entend a été posé **simplement, pour que ça marche**, avec les composants de l'accueil. Demain, on le reprend avec toi, une chose à la fois, sur les planches (`.\Start-Mikky.ps1 -Boards`), puis dans l'app.

**Seul l'accueil est validé** (2026-10-02, `design.md` §7 « Nouvel accueil »). Tout le reste de cette liste n'a pas été revu ensemble depuis.

## Comment on travaille demain

1. Pour chaque point : une planche avec les variantes côte à côte, vivantes ; tu choisis ; on retire les autres ; la décision va dans `design.md`.
2. Les animations **une par une** : un état ou une émote, on la règle, on passe à la suivante. L'écran `mikky.exe --tuning` montre tous les états ; on y ajoute ce qui manque.
3. Les sons **un par un** aussi, avec Mikky qui bouge en même temps : on écoute en situation, pas un fichier seul.
4. Rien ne change dans l'accueil validé, sauf si tu le demandes.

## Ce qui est en place (à juger, pas à reconstruire)

| Où | Ce qui existe | Code |
|---|---|---|
| Table des réactions | Pour chaque changement d'agent : un geste, une émote, un son et une phrase (« attend ton feu vert »…). Changer d'outil ne fait rien ; seul le début du travail fait un son. | `packages/mikky_engine/lib/src/mikky/reactions.dart` (`reactionTo`, `reactionToAnswer`) |
| Mikky au fil de la journée | Il s'endort après 10 min sans agent ni geste de ta part (bâillement, puis il dort). Il se réveille au moindre événement ou quand ta souris passe sur l'île. | `MikkyDirector` (même fichier) |
| Mikky et toi | Clic sur Mikky, île ouverte : une petite gifle (il est agacé) ; trois clics en 1,7 s : il a le vertige ; souris immobile 1,9 s sur lui : amour. Au bord : coucou. | `mikky.dart` (`slap`, `boop`, `hover`), `island_view.dart` |
| La demande apportée | La carte qui montre la tâche, l'étape du plan (« 2/3 · … »), les derniers mots de l'agent, ses 3 dernières actions (+N −M), puis la demande. En haut, l'île ouverte passe à **450 × 260** (avant 430 × 178), Mikky à gauche. À droite, une page « Pour toi », Mikky en haut à gauche. | `app/lib/island/content/brief_view.dart`, `app/lib/side/brief_page.dart`, `brief.dart` du moteur |
| Sons | Les 7 sons PSP, un par signal (tableau plus bas) ; Sons oui / non et trois volumes dans le menu ; jamais deux fois le même en 150 ms, au plus 3 en 0,6 s. | `app/lib/sound/sound_board.dart`, natif `app/windows/runner/sound.cpp` |
| Hooks | La page « Hooks Claude Code / Codex » (état, diff exact, Installer) ; la demande d'une session extérieure, sur la carte, avec « Répondre dans le terminal ». | `app/lib/side/hooks_page.dart` |
| Raccourcis | Ctrl + Alt + A : la demande en attente ; Ctrl + Alt + Espace : ouvrir ou fermer ; Ctrl + Alt + M : couper ou remettre les sons. Une case dans le menu les désactive. | `island_view.dart` (`_setHotkeys`) |

## 1. Les animations de Mikky, une par une

Validées avant (on n'y touche que si tu le veux) : **travaille**, **attend ton feu vert**, **amour**, **terminé**, **surpris** (`design.md` §6). Réfléchit et cherche gardent l'animation de travail (ta décision du 2026-10-01).

**À faire ensemble** (dans cet ordre, du plus vu au plus rare) :
1. **Apporter une demande** (nouveau, le plus important) : comment Mikky « amène » la demande. Pistes à essayer : il sort de la petite île vers la bulle puis revient avec ; il saute vers la carte ; il tend une oreille vers la commande ; il prend la forme du « ! » le temps d'arriver. Aujourd'hui : son geste « alerte » et son état « attend ».
2. **Pose une question** : aujourd'hui une oreille qui bouge et la tête penchée. À dessiner : différent de « attend » au premier coup d'œil.
3. **Erreur** : aujourd'hui une secousse et des yeux plats. Le « ! » rouge vient des pixels de l'accueil ; Mikky, lui, n'a pas d'état d'erreur validé.
4. **Limite atteinte** : yeux fatigués, gouttes de sueur (repris de Mochi, jamais revu).
5. **Il s'endort et se réveille** (nouveau) : bâillement puis yeux fermés, « z » ; réveil par un clignement. À voir : au bout de combien de temps (10 min aujourd'hui), et s'il dort aussi île fermée.
6. **Ta réponse** : Oui → content (petit saut) ; Non → secousse ; Relancer → petit saut. À dessiner : une réponse doit se sentir « prise ».
7. **Coucou au bord** : aujourd'hui un clignement et une oreille. Mochi sort et fait coucou avec les mains ; Mikky n'a pas de mains : avec les oreilles ?
8. **Gifle et vertige** : agacé (yeux en fente, oreilles basses), vertige (roulade double, yeux en spirale). Repris de Mochi, jamais vus ensemble.
9. **Un autre agent change** pendant que Mikky en suit un : aujourd'hui seulement le son. À décider : un regard vers le coin ? une oreille ?

Pour chacune : la durée, le ressort (pas trop gluant, `design.md` §8), et si elle s'arrête quand Windows demande moins d'animations.

## 2. Les sons, un par un

Aujourd'hui (un seul tableau, `sound_board.dart`) :

| Signal | Quand | Fichier |
|---|---|---|
| `hello` | Mikky démarre | `launch` (**4 s, sûrement trop long**) |
| `open` / `close` | l'île s'ouvre / se ferme | `folder_open` / `folder_close` |
| `peek` | coucou au bord | `navigate` |
| `navigate` / `back` | une page arrive / on revient | `navigate` / `back` |
| `select` | ignorer, volume, sons remis | `select` |
| `launch` | un agent se met au travail | `navigate` |
| `approval` / `question` | un agent attend ton feu vert / te pose une question | `folder_open` |
| `error` / `rateLimited` | erreur / limite | `back` |
| `finished` | un agent a fini | `retroachievements` |
| `approve` / `deny` | tu dis Oui / Non | `select` / `back` |
| `love` / `slap` / `dizzy` | amour / gifle / vertige | `navigate` / `back` / `back` |
| `sleep` / `wake` | il s'endort / se réveille | `folder_close` / `folder_open` |

À décider ensemble :
- quels signaux restent **muets** (Mochi ne fait aucun bruit pour ce qui change sans rien demander) ; « un agent se met au travail » à chaque tour risque d'être trop fréquent, et **l'ouverture / la fermeture jouent aussi à chaque survol** de l'île ;
- un son **à part pour ce qui te demande quelque chose** (aujourd'hui `folder_open`, le même que l'ouverture) ;
- le volume par défaut (moyen, 50 %) ;
- **les sons pour la distribution** : les fichiers PSP (Sony) et `retroachievements` ne sont pas à nous. Ils restent sur ton PC, hors de git (le dépôt est public, voir `app/assets/sounds/README.md`). Avant de distribuer Mikky : des sons libres (CC0) ou faits pour lui, dans la même ambiance.

## 3. Les écrans qui n'ont pas été revus

Par ordre d'importance :
1. **La demande en haut** (île ouverte 450 × 260) : la disposition de la carte, ce qui se voit d'abord (la commande ? la tâche ?), les « Tâche / Étape / Dit », les actions récentes, la barre Oui / Non / Toujours, « 1/3 », « Voir l'agent », « Répondre dans le terminal ». La taille de l'île pour une demande.
2. **La demande à droite** (page « Pour toi ») : la même chose en hauteur, avec Mikky en haut à gauche ; le titre.
3. **Une question à choix** : la carte de question utilise encore des boutons en capsule (`MButton`, exception notée dans `design.md` §7) ; la passer à notre style.
4. **Terminé** : la carte (résumé, fichiers modifiés avec +N −M, OK) n'apparaît que dans la carte de demande ; en haut, l'île ne s'ouvre plus pour « terminé » (décision du 2026-10-01). À décider : où le résumé et les fichiers se voient (la petite île ? la tuile ?).
5. **Les actions rapides depuis l'accueil** (déjà prévu, `design.md` §12.1) : valider Oui / Non depuis la tuile ; la carte de demande peut servir de modèle.
6. **La page d'un agent** (Suivi / Chat) : refaite le 2026-09-30, pas revue avec le nouvel accueil ; la demande d'un hook y apparaît maintenant en carte d'attente.
7. **La page Hooks** : texte, diff en mono, Installer / Annuler.
8. **Le menu du clic droit** (« trop gluant, bouncy, perturbant ») : il a grandi encore (Sons, Volume, Raccourcis, Hooks Claude Code, Hooks Codex). C'est le moment d'en faire **une vraie page Réglages** (Apparence, Sons, Raccourcis, Agents, Hooks, Notifications), comme proposé dans `idees.md` §9.
9. **La petite île** (en haut et à droite) et **la bulle** : validées sur la planche le 2026-10-01, jamais vues dans l'app avec les cinq états.
10. **Nouvel agent, connexion, historique** (l'historique est un essai), **notifications Windows** (leurs phrases), **bandeau du moteur** (connexion, reconnexion), **états vides** (l'île ouverte sans agent montre encore « Clic droit ▸ Démo… »).

## 4. Planches à ajouter (avant la séance, si possible)

- **« Réactions »** : un bouton par événement (travaille, attend, question, erreur, limite, terminé, Oui, Non, gifle, vertige, amour, dort, réveil, coucou) qui joue l'animation **et le son** sur un grand Mikky ; la même chose sur la petite île en haut et à droite.
- **« Demandes »** : `BriefView` dans tous ses cas (commande, fichier avec +N −M, question, erreur, terminé, limite, demande d'un hook), en haut (328 px de large) et à droite (page), clair et sombre, avec de fausses sessions (`fake_sessions.dart`).
- **« Sons »** : chaque signal avec son fichier, un bouton Écouter, et les variantes à comparer.
- Ajouter **la page Hooks** et **la page Réglages** (à dessiner) à la planche Agent.

## 5. Ce qui n'est pas visuel mais se décide en même temps

- L'ordre de Ctrl + Alt + A, Espace, M : te conviennent-ils ? (Windows refuse un raccourci déjà pris par une autre app ; il est alors ignoré, sans message pour l'instant.)
- Le volume et les sons « toujours » / « seulement quand l'île est ouverte ».
- Après une réponse depuis la carte, à droite : retour à l'accueil (aujourd'hui) ou rester sur la page de l'agent ?
