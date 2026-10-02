# Mikky

Mikky est une petite mascotte (un chat noir aux grands yeux) qui vit dans une île flottante au bord de l'écran, et qui lance et suit tes agents Claude Code et Codex.

- Où on en est : [docs/superpowers/reprise.md](docs/superpowers/reprise.md)
- Le design : [docs/superpowers/design.md](docs/superpowers/design.md) ; référence visuelle : les planches (`.\Start-Mikky.ps1 -Boards`)
- L'app Windows : [app/](app/) ; le moteur Rust : [daemon/](daemon/)

Architecture R2/R3 : Flutter affiche, `mikkyd` (Rust) lance et suit les agents et conserve les métadonnées dans SQLite. Windows et WSL ont chacun leur backend, actif après fermeture de l'écran. La page **Technique** de `mikky.exe --kit` explique ce fonctionnement et la suite prévue. Le build Windows embarque les deux backends et demande Cargo sous Windows ainsi que Rust dans WSL `Ubuntu`.

## Étapes futures

La [feuille de route détaillée](docs/superpowers/reprise.md#prochaines-étapes-dans-lordre) donne l'ordre et les critères du MVP. Les priorités sont :

1. Valider de bout en bout Claude Code et Codex sous Windows et WSL : lancement, permissions, plusieurs agents, arrêt et reconnexion.
2. Montrer clairement les agents contrôlés par Mikky et les sessions extérieures seulement observées. Le PID de l'adaptateur ACP lancé par Mikky est affiché ; restent la vérification des processus et la détection fiable des agents lancés ailleurs.
3. Borner la mémoire et les files d'événements du moteur Rust, puis fiabiliser l'installation, les mises à jour et la distribution. Les hooks de Coucou sont une piste optionnelle pour les sessions Claude extérieures.
4. Garder SQLite pour le MVP ; ajouter tables, index, migrations et sauvegardes quand les requêtes le justifient. DuckDB ne servirait qu'à des analyses volumineuses.
5. Après le MVP, construire une mémoire utilisateur locale, recherchable et corrigeable, partagée aux agents par une API avec droits explicites. Cette API pourra servir plus tard à une installation personnelle hébergée ; une base serveur ne sera nécessaire que pour un service multi-utilisateur.

La grande fenêtre et le VPS multi-machine restent reportés.

## Lancer l’application

Prérequis de compilation : Flutter Windows, Visual Studio avec C++, Cargo Windows et Rust dans WSL `Ubuntu`. Prérequis des agents : Node.js 22+ sous Windows, Claude Code et/ou Codex installés et connectés avec leur abonnement. Le backend installe ses adaptateurs ACP au premier lancement d’un agent ; sous WSL il prépare aussi son Node privé.

```powershell
.\scripts\Build-Windows.ps1
.\Start-Mikky.ps1                  # île flottante
.\Start-Mikky.ps1 -Island          # île / zone de notification
.\Start-Mikky.ps1 -Boards          # planches, dont Technique
.\Start-Mikky.ps1 -InstallStartup  # île + moteur à la connexion Windows
```

Le bundle complet se trouve dans `dist/Mikky-<date>/` : conserver `data`, les DLL et les deux exécutables Rust à côté de `mikky.exe`. Fermer un écran laisse les agents actifs. L’arrêt global et le démarrage Windows se règlent dans le menu du moteur. Les anciens moteurs sont mis à jour automatiquement seulement s’ils n’ont aucun agent actif ; sinon terminer leurs agents avant la mise à jour. WSL est optionnel à l’exécution : son indisponibilité n’empêche pas les agents Windows.

## Vérifier le code

Dans `daemon/` : `cargo build`, `cargo build --examples`, `cargo test --workspace`. Dans `packages/mikky_engine/` et `packages/mikky_agents/` : `dart analyze`, `dart test`. Dans `app/` : `flutter analyze`, `flutter test`. Les tests de parité relisent les enregistrements Claude/Codex ; les anciennes implémentations Dart sont isolées dans `tool/legacy` et `test/support/readers`, jamais utilisées par l’app. Le scénario WSL s’active avec `MIKKY_TEST_WSL=1` et le binaire Linux embarqué à côté du daemon de test (remplacement **atomique**, jamais écrasé s’il est chargé).

## Mesures

| Jalon | Date | Île cachée (CPU) | Île compacte (CPU) | Mémoire | Notes |
|---|---|---|---|---|---|
| J0 | 2026-09-28 | 0,03 % du total (94 ms sur 30 s, souris en mouvement 1/3 du temps) | non mesuré (pas encore d'animation continue) | 73 Mo | build release, écran 1920 × 1080 à 100 %, 12 cœurs |
| Position à droite + contenu | 2026-09-28 | — | carte à droite **ouverte**, contenu démo : 1,13 % du total | 58 Mo (Gestionnaire des tâches), 160 Mo réservés | la mémoire privée réservée inclut le moteur graphique |
| Mikky + shader | 2026-09-28 | 0,013 % du total | île **ouverte**, Mikky animé : 0,85 % du total (10 % d'un cœur) | 99 Mo (working set), 142 Mo privés | même machine ; la mémoire privée approche la limite de 150 Mo, à surveiller |
