> **Décision du 1 octobre 2026 : l'île flottante reste l'interface de Mikky.** La grande fenêtre de monitoring est reportée et conservée sur `feature/r4-workspace`. Sur `main`, `Start-Mikky.ps1` ouvre l'île, avec sa petite fenêtre de sessions ; le backend Rust et la planche Technique sont conservés. Les mentions de livraison de la grande fenêtre ci-dessous décrivent l'étape antérieure, désormais retirée de `main`.
# Mikky

Mikky est une petite mascotte (un chat noir aux grands yeux) qui vit dans une île en haut de l'écran et, à terme, suit et pilote tes agents Claude Code sur le PC, le téléphone et un VPS.

- Spec de l'étape 1 : [docs/superpowers/specs/2026-09-28-etape-1-design.md](docs/superpowers/specs/2026-09-28-etape-1-design.md)
- Référence visuelle : les planches de `mikky.exe --kit` (les prototypes HTML sont historiques).
- Plan de l'étape 1 : [docs/superpowers/plans/2026-09-28-etape-1-plan.md](docs/superpowers/plans/2026-09-28-etape-1-plan.md)
- L'app Windows : [app/](app/)

Architecture R2/R3 : Flutter affiche, `mikkyd` (Rust) lance et suit les agents et conserve les métadonnées dans SQLite. Windows et WSL ont chacun leur backend, actif après fermeture de l'écran. [État vérifié et limites restantes](docs/superpowers/r3-verification.md). La page **Technique** de `mikky.exe --kit` explique ce fonctionnement et la suite prévue. Le build Windows embarque les deux backends et demande Cargo sous Windows ainsi que Rust dans WSL `Ubuntu`.

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
