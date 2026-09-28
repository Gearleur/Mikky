# Mikky — guide for AI coding agents

Mikky is a small black cat mascot with big white eyes living in an "island" at the top of the screen. Step 1: Mikky + island on Windows with fake agents (demo mode). Later: real Claude Code agents (step 2), Flutter mobile (step 3), a Rust daemon `mikkyd` on PC + VPS where agents talk on a shared channel (step 4). Inspired by the Coucou macOS app (`~/projects/coucou`, see `NotchBuddy/Sources/App/BotEngine.swift` for the animation technique).

## Where things are
- `docs/superpowers/specs/2026-09-28-etape-1-design.md` — step 1 spec (in French). **Status: approved by the user on 2026-09-28.**
- `docs/superpowers/plans/2026-09-28-etape-1-plan.md` — step 1 plan. J0 (overlay) done and validated on 2026-09-28; next: J1 (`packages/mikky_engine`), detail it in the plan first.
- `app/` — the Flutter Windows app. Overlay native code in `app/windows/runner/` (`flutter_window.cpp`: channel `mikky/overlay`, `WH_MOUSE_LL` hook, click-through toggle). `lib/island/j0_island.dart` is a J0 stand-in, to be replaced from J1 on.
- `design/prototypes/` — validated HTML prototypes, the visual source of truth. `ile-noir-et-blanc.html` = the validated island (dark "A" + "blanc pur"); `mascotte-variantes.html` = mascot (card "S", without the tail); `ile-trois-noirs.html` = exploration only.

## Decisions (do not re-litigate)
- Flutter everywhere (desktop now, mobile later). Rust only for `mikkyd` later. Windows only for step 1.
- Island = SDF fragment shader (squircle, smooth-min drop and split bubble). Values are in the spec §3.
- Mikky: no mouth, no feet, no pupils; tail only in some states later. Ears carry emotion.
- Dots grid: dark theme only, only while an agent works. Light theme: Apple system colors, no glow, no dots.

## Environment
- Repo lives on Windows at `C:\Users\alexa\projet\mikky` (moved out of WSL on 2026-09-28; from WSL: `/mnt/c/Users/alexa/projet/mikky`). Windows Flutter at `C:\dev\flutter` (3.47.5) with Visual Studio 2022 C++ workload and Android SDK. Always run `flutter`/`dart` with the Windows install (from WSL: `cmd.exe /c "C:\dev\flutter\bin\flutter.bat ..."`), never the WSL Flutter, on this repo.

## Rules
- Talk to the user in French.
- No telemetry. Secrets in the OS credential store, never on disk or in git.
- Never block Claude Code; never approve a permission without an explicit click (from step 2).
- 0 % CPU when the island is hidden.
- Visual changes must match `design/prototypes/`.
