# Mikky — app Windows

Lancer (toujours avec le Flutter de Windows) :

```
C:\dev\flutter\bin\flutter.bat run -d windows
```

L'île est cachée au démarrage : amène la souris tout en haut au centre de l'écran principal pour la faire sortir. Clic : ouvrir ; île ouverte, clic sur Mikky : boop, ailleurs : refermer. Clic droit : menu (thème automatique / noir / blanc, quitter). Le thème choisi est gardé dans `%APPDATA%\Mikky\settings.json`.

Le code natif de l'overlay (fenêtre transparente, clics traversants, hook souris) est dans `windows/runner/flutter_window.cpp` et `win32_window.cpp`.
