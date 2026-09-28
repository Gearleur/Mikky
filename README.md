# Mikky

Mikky est une petite mascotte (un chat noir aux grands yeux) qui vit dans une île en haut de l'écran et, à terme, suit et pilote tes agents Claude Code sur le PC, le téléphone et un VPS.

- Spec de l'étape 1 : [docs/superpowers/specs/2026-09-28-etape-1-design.md](docs/superpowers/specs/2026-09-28-etape-1-design.md)
- Prototypes validés (à ouvrir dans un navigateur) : [design/prototypes/](design/prototypes/)
- Plan de l'étape 1 : [docs/superpowers/plans/2026-09-28-etape-1-plan.md](docs/superpowers/plans/2026-09-28-etape-1-plan.md)
- L'app Windows : [app/](app/)

## Mesures

| Jalon | Date | Île cachée (CPU) | Île compacte (CPU) | Mémoire | Notes |
|---|---|---|---|---|---|
| J0 | 2026-09-28 | 0,03 % du total (94 ms sur 30 s, souris en mouvement 1/3 du temps) | non mesuré (pas encore d'animation continue) | 73 Mo | build release, écran 1920 × 1080 à 100 %, 12 cœurs |
| Position à droite + contenu | 2026-09-28 | — | carte à droite **ouverte**, contenu démo : 1,13 % du total | 58 Mo (Gestionnaire des tâches), 160 Mo réservés | la mémoire privée réservée inclut le moteur graphique |
| Mikky + shader | 2026-09-28 | 0,013 % du total | île **ouverte**, Mikky animé : 0,85 % du total (10 % d'un cœur) | 99 Mo (working set), 142 Mo privés | même machine ; la mémoire privée approche la limite de 150 Mo, à surveiller |
