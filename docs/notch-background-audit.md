# Notch : sons et activité en arrière-plan

Audit du 16 octobre 2026, à partir du rapport live
`mikky-notch-test-1792153853002645-report.json` et du code exécuté par Mikky.

## Défauts corrigés

- Les boutons Terminer et Relance auto étaient dans une zone de texte
  sélectionnable. Les actions partagées sont exclues de la sélection : curseur
  main et clic restent utilisables au milieu du fil.
- La mise en sommeil automatique après dix minutes jouait un son même sans
  agent. Le bâillement reste, cette transition automatique devient silencieuse.
- L’inventaire des sessions pouvait exposer chaque page d’historique comme un
  nouvel état. Il émet désormais un seul état complet par conversation, marqué
  comme restauration silencieuse. Une reconstruction après réécriture l’est aussi.
- Les titres, jetons, compteurs de contexte et limites de compte ne constituent
  plus une preuve d’activité. Ils ne repoussent plus l’expiration d’un ancien tour
  ni la date d’activité de sa conversation, et ne réactivent plus une fin ignorée.
- Retirer une conversation de l’île n’efface plus immédiatement le souvenir de
  son dernier état : son rappel ne rejoue pas la fin. La mémoire est bornée.
- Les notifications Windows suivent la même règle, car elles peuvent produire
  leur propre son. Les inventaires des demandes de hooks sont également silencieux.
- Un sous-agent sans événement de fin avait besoin de sa propre échéance
  d’inactivité. Elle est maintenant prévue, même si son parent avait déjà fini ;
  son expiration n’est pas annoncée comme une nouvelle tâche terminée.

Les nouvelles demandes et les transitions réellement observées gardent leurs
sons. Une notification reçue après démarrage ne devient pas automatiquement
« une nouvelle activité » simplement parce que le fichier vient d’être relu.

## Ce qui tourne réellement

- Rust surveille les répertoires Claude/Codex par événements de fichiers natifs ;
  les événements de simple accès sont ignorés. La lecture incrémentale n’appelle
  aucun modèle et ne relance pas les conversations.
- Le relais de hook est invoqué par l’application source à l’occasion d’un
  événement. Il recherche ses processus parents pour retrouver la fenêtre
  d’origine, puis se termine. Cette recherche n’est pas un sondage continu et ne
  décide pas à elle seule de l’état « au travail ».
- Les processus d’une application ouverte ne prouvent pas qu’une conversation
  exécute une tâche. Pour les sessions extérieures, Mikky suit les événements de
  conversation ; sans nouvelles pendant quinze minutes, un tour resté ouvert est
  considéré inactif. Ce délai ne certifie pas la vie d’un processus.
- Le lanceur de mikkyd et son processus enfant ne sont pas deux sources audio :
  les sons sont joués par l’interface de l’île. Les planches n’ouvrent pas le
  service de suivi des agents.

## Vérifications

Les tests couvrent le curseur dans le vrai conteneur sélectionnable, une
conversation de plus de mille événements chargée en plusieurs pages, les
inventaires de hooks, les compteurs tardifs, le rappel d’une fin et dix minutes
de repos simulées. Ils conservent les annonces de nouveaux événements.

Diagnostic en lecture seule, dans `packages/mikky_agents` :

```powershell
C:\dev\flutter\bin\dart.bat run tool/state_check.dart --audit-sounds
```

`audibleDuringLoad` expose les décisions sonores pendant le chargement et une
courte observation. Il ne lit pas le son des haut-parleurs ; il ne contient ni
prompts, ni titres, ni chemins de conversations, ni secrets. Une nouvelle activité
réelle pendant cette observation peut légitimement y apparaître.
