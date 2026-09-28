# Mikky — guide for AI coding agents

Mikky is a small black cat mascot with big white eyes living in an "island" at the top of the screen. Step 1: Mikky + island on Windows with fake agents (demo mode). Later: real Claude Code agents (step 2), Flutter mobile (step 3), a Rust daemon `mikkyd` on PC + VPS where agents talk on a shared channel (step 4). Inspired by the Coucou macOS app (`~/projects/coucou`, see `NotchBuddy/Sources/App/BotEngine.swift` for the animation technique).

## Where things are
- `docs/superpowers/specs/2026-09-28-etape-1-design.md` — step 1 spec (in French). **Status: waiting for the user's review.** Next step after approval: write the implementation plan (superpowers:writing-plans).
- `design/prototypes/` — validated HTML prototypes, the visual source of truth. `ile-noir-et-blanc.html` = the validated island (dark "A" + "blanc pur"); `mascotte-variantes.html` = mascot (card "S", without the tail); `ile-trois-noirs.html` = exploration only.

## Decisions (do not re-litigate)
- Flutter everywhere (desktop now, mobile later). Rust only for `mikkyd` later. Windows only for step 1.
- Island = SDF fragment shader (squircle, smooth-min drop and split bubble). Values are in the spec §3.
- Mikky: no mouth, no feet, no pupils; tail only in some states later. Ears carry emotion.
- Dots grid: dark theme only, only while an agent works. Light theme: Apple system colors, no glow, no dots.

## Environment
- Repo lives in WSL. Windows Flutter at `C:\dev\flutter` (3.38.3). Visual Studio C++ workload not installed yet (the user installs it). Building the Windows app from the `\\wsl.localhost` path must be validated in milestone J0 (fallback: sync `app/` to a Windows folder).

## Rules
- Talk to the user in French.
- No telemetry. Secrets in the OS credential store, never on disk or in git.
- Never block Claude Code; never approve a permission without an explicit click (from step 2).
- 0 % CPU when the island is hidden.
- Visual changes must match `design/prototypes/`.
