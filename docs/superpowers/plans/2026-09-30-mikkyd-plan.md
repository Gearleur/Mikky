# Plan — `mikkyd` (R0 à R7)

Spec : `specs/2026-09-30-mikkyd-design.md` (validée le 2026-09-30). Code : `daemon/` (cargo workspace).

## Avancement

### R0 — Préparer ✔ (2026-09-30)

- Rust 1.98.1 installé avec rustup, sous Windows (`%USERPROFILE%\.cargo\bin`) et dans WSL (`~/.cargo/bin`).
- `daemon/` : workspace cargo (édition 2024), premier crate `mikky-acp`.
- **Choix : le SDK officiel ACP** (`agent-client-protocol` 2.2.0, Apache-2.0, https://github.com/agentclientprotocol/rust-sdk). Il fait le JSON-RPC et donne des types pour tout le protocole. Mikky lance lui-même le processus de l'adaptateur (`mikky_acp::spawn`, pour le job object et WSL) et donne ses tuyaux au SDK (`ByteStreams`).
- **Essai réussi** (`cargo run --example probe -- <index.js de l'adaptateur> [dossier]`, sans message envoyé, donc gratuit) : Claude (`claude-agent-acp` 0.84.0) et Codex (`codex-acp` 2.0.0), **sous Windows et dans WSL** (binaire Linux) : `initialize`, `session/new`, modes, commandes « / » reçues.
- Crates prévus, à créer au fil des étapes : `mikky-proto`, `mikky-run`, `mikky-watch`, `mikky-store`, `mikky-bus`, `mikky-api`, et le binaire `mikkyd`.

À vérifier en R1 : ce que le SDK permet hors du protocole stable. Aujourd'hui, Mikky annonce `elicitation.form` pour que Claude puisse poser ses questions à choix : il faudra passer par les fonctions `unstable_*` du SDK ou par des messages non typés.

### R1 — `mikkyd` fait ce que fait `mikky_agents`, sur le PC

À faire.

### R2 à R7

Voir la spec, §10.

## Notes

- Git Bash ne voit `cargo` qu'après redémarrage du terminal : sinon `export PATH="$HOME/.cargo/bin:$PATH"`.
- Dans WSL, compiler avec `CARGO_TARGET_DIR=$HOME/.cache/mikky-daemon-target` (bien plus rapide que sur `/mnt/c`), et mettre le Node privé dans le PATH (`~/.local/share/mikky/node/bin`).
- Ouvrir une session sans message ne laisse pas de session dans Claude ni dans Codex ; Claude crée juste un dossier de projet vide dans `~/.claude/projects/`.
