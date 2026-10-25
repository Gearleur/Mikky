# Tester la notch en direct

Depuis le dépôt, dans PowerShell :

```powershell
.\scripts\Test-Notch.ps1
```

Le script utilise l’île et le moteur Mikky locaux. Il crée deux conversations **TEST NOTCH**, avec des événements et demandes simulés qui passent par les vrais lecteurs et canaux de réponse. Aucun modèle n’est appelé, aucune commande affichée n’est exécutée, aucune configuration de hooks n’est modifiée.

1. Dans la console, **Entrée** démarre le parcours.
2. Réponds aux demandes dans la notch. Les deux premières servent à essayer **Oui**, puis **Non** ; les deux décisions sont acceptées sans bloquer la suite.
3. Aux pauses, **Entrée** continue. Tu peux écrire une remarque puis Entrée : elle sera enregistrée avec l’étape.
4. **q** à une pause ou **Ctrl+C** pendant le parcours termine le test et nettoie ses conversations. Garde la console ouverte jusqu’au message de nettoyage.

## Parcours

Activité → Oui → Non → choix simple → choix multiples → réponse libre avec Autre → série de questions → texte long, Contexte/Question et Plus tard → deux agents → deux questions simultanées → erreur Codex → limite Claude simulée → reprise dans la même conversation → résolution de l’erreur Codex → fin des deux agents et historique.

Dans une série, le dernier choix simple reste sélectionné jusqu’à **Envoyer**. Reviens en arrière pour le modifier avant l’envoi. Entre les deux agents en attente, **Répondre à cet agent** permet d’identifier la nouvelle conversation avant de répondre. L’erreur Codex reste volontairement active pendant la limite et la reprise de Claude ; elle est résolue juste avant la fin, où aucun point d’exclamation ni étoile de travail ne doit rester.

Vérifie notamment l’identité de l’agent, le regroupement indicateurs/question/choix, le défilement, les brouillons quand tu reviens en arrière ou diffères, la séparation des deux agents, les sons et l’absence de doublons à la reprise. La limite affichée est fictive : ne programme pas de relance automatique pour ce test.

Chaque demande peut expirer après environ 105 secondes, comme un vrai hook. Sans réponse, le script la repropose ; après dix essais il termine avec une erreur. Les pauses de la console n’ont pas cette limite.

Les réponses et remarques sont enregistrées dans `dist/mikky-notch-test-<identifiant>-report.json`. Le nettoyage masque seulement les identifiants de test et supprime leurs fichiers et copies indexées ; il ne supprime pas les conversations réelles. Les marques de suppression de ces identifiants restent dans les métadonnées pour que les fenêtres déjà ouvertes cessent de les afficher. Une fermeture brutale du terminal peut empêcher le nettoyage.

## Vérification automatique

```powershell
.\scripts\Test-Notch.ps1 -Verify
```

Utilise le moteur debug du dépôt, un dossier temporaire et une base en mémoire. Les réponses sont données automatiquement, les neuf retours sont comptés et les états travail/erreur/limite/reprise/fin sont vérifiés. Ce contrôle ne juge pas l’apparence ni la sortie audio : c’est le but du parcours manuel.

Pour tester un binaire d’interface précis :

```powershell
.\scripts\Test-Notch.ps1 -AppPath 'C:\chemin\du\bundle\mikky.exe'
```

Seule l’île de ce dépôt est remplacée si nécessaire ; le daemon, les agents réels et les fenêtres de planches restent ouverts. Sans `-AppPath`, le script utilise le binaire de revue enregistré dans `dist/notch-test-app.txt` s’il existe ; sinon il garde l’île déjà lancée ou démarre la version habituelle. Le pointeur de version habituel `dist/current.txt` reste inchangé.
