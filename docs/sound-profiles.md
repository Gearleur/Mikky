# Configurer les sons de Mikky

Les associations entre événements et sons sont définies dans
[`app/assets/config/sounds.json`](../app/assets/config/sounds.json).
Ce profil intégré conserve les sons actuels. Il est chargé avant le démarrage
de l’île ; le lecteur audio ne contient plus la liste des associations.

## Personnalisation sans recompilation

Sous Windows, créer ou modifier **`%APPDATA%\Mikky\sounds.json`**, puis
redémarrer Mikky. Ce fichier personnel reste indépendant des mises à jour
de l’application, du thème graphique et des préférences de volume.

On peut copier le profil intégré entier, ou ne définir que les événements
à changer :

```json
{
  "version": 1,
  "sounds": {
    "open": "select_2",
    "close": null
  }
}
```

Cet exemple joue `select_2.mp3` à l’ouverture et garde la fermeture silencieuse.
Les événements absents du fichier personnel héritent du profil intégré.
Les noms d’événements disponibles figurent dans le profil intégré, par exemple
`hello`, `open`, `close`, `send`, `approval`, `question`, `finished` et `error`.

Le nom d’un son est celui d’un MP3 déjà présent dans
`data/flutter_assets/assets/sounds/` du dossier de l’application : **sans
extension, sans chemin**, avec uniquement lettres minuscules, chiffres et
soulignement, de 1 à 64 caractères. Ajouter un nouveau son nécessite de placer
son MP3 dans ce dossier, puis d’utiliser son nom dans le JSON ; aucun changement
de code n’est nécessaire. Un fichier MP3 absent reste silencieux, comme avant.
Les fichiers audio personnels ne sont pas distribués dans le dépôt public.

## Comportement conservé

- Le volume et l’activation restent dans les paramètres de Mikky. Le profil
  sonore ne les remplace pas.
- `null` désactive uniquement l’événement concerné.
- Les protections contre les sons répétés et trop nombreux restent actives.
- Un événement inconnu, un nom de son invalide, un champ inconnu, une erreur
  JSON ou une version non prise en charge font rejeter le profil personnel
  entier. Mikky utilise alors le profil intégré et écrit un diagnostic.
- Le fichier personnel n’est jamais modifié par le chargement. Si le profil
  intégré est lui-même illisible, l’interface démarre avec les sons silencieux.
- Le chargement se fait une seule fois au démarrage : aucun suivi de fichier
  ni traitement supplémentaire quand l’île est cachée.

Les **couleurs de marque** (mascotte, logos et palettes signature bleu/orange)
restent fixes et ne font pas partie d’un profil personnalisable. Les sons et
les couleurs de l’interface sont deux sujets indépendants.
