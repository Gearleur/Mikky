# Plan — `mikkyd` (R0 à R7)

Spec : `specs/2026-09-30-mikkyd-design.md`. Code : `daemon/`. Où on en est et la suite : `reprise.md`.

| Étape | État |
| --- | --- |
| R0 · Rust, essais ACP Windows et WSL | fait |
| R1 · `mikkyd` fait tourner les agents ; API WebSocket locale, jeton dans le coffre de Windows | fait |
| R2 · sessions extérieures lues en Rust ; moteur natif dans WSL | fait |
| R3 · tout le travail d'agents en Rust (lancement, installation, connexion, SQLite, protocole 3) ; l'app n'est qu'un écran | fait, en usage réel à fiabiliser |
| R4 · grande fenêtre | reportée (`feature/r4-workspace`) |
| R5 · autres outils | à faire |
| R6 · équipes, canal entre agents | recherche, puis spec |
| R7 · VPS par tunnel SSH | plus tard |

Mesure (30 septembre, release, sans agent) : 39 Mio résidents, démarrage et connexion en 209 ms, binaire de 3,9 Mio, rien au repos.

## Notes

- **Pas de SDK ACP** : `mikky-acp` est un petit client JSON-RPC qui voit chaque message tel quel (et `elicitation/create`).
- **Ordre des messages** : enregistrer chaque message au moment où on le lit ou l'écrit, avant que la requête qu'il termine se résolve.
- **Rust** : `m.lock().unwrap().a + m.lock().unwrap().b` bloque pour toujours.
- **Dart** : `DaemonClient` utilise un flux `sync: true`, sinon une réponse passe devant les notifications qui la précèdent.
- **WSL** :
  - compiler avec `CARGO_TARGET_DIR=$HOME/.cache/mikky-daemon-target` ;
  - Node privé dans `~/.local/share/mikky/node/bin` ;
  - un ancien moteur n'est mis à jour que si son inventaire est vide.
- Git Bash ne voit `cargo` qu'après redémarrage du terminal : sinon `export PATH="$HOME/.cargo/bin:$PATH"`.
