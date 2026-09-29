# Mikky — guide for AI coding agents

Mikky is a small black cat mascot with big white eyes living in an "island" at the top of the screen. Since 2026-09-29 the goal is wider: a simple Paperclip-like companion that runs and tracks Claude Code and Codex agents (see `docs/superpowers/idees.md`). Step 1: Mikky + island on Windows with fake agents (demo mode). Later: real Claude Code agents (step 2), Flutter mobile (step 3), a Rust daemon `mikkyd` on PC + VPS where agents talk on a shared channel (step 4). Inspired by the Coucou macOS app (`~/projects/coucou`, see `NotchBuddy/Sources/App/BotEngine.swift` for the animation technique).

## Where things are
- **`docs/superpowers/reprise.md` — read first: where we are, the art direction the user validated, what is left, known pitfalls.**
- `docs/superpowers/idees.md` — all feature ideas (Paperclip-like companion, loops, LocalSend, VPS, mails, mini-apps) and the chosen MVP (2026-09-29). Nothing there is decided beyond the MVP and the validated design.
- `docs/superpowers/specs/2026-09-28-etape-1-design.md` — step 1 spec (in French). **Status: approved by the user on 2026-09-28.**
- `docs/superpowers/plans/2026-09-28-etape-1-plan.md` — step 1 plan and progress. J0, J1, J2 done (J2 still to validate with the user); J3 partly. See its "Avancement" section.
- `packages/mikky_engine/` — pure Dart engine: Mikky (states, emotes, forms, geometry), island rules (`IslandMachine`), agents (`AgentSource`, `DemoAgentSource`). Tests: `C:\dev\flutter\bin\dart.bat test` in that folder.
- `app/` — the Flutter Windows app. Overlay native code in `app/windows/runner/` (`flutter_window.cpp`: channel `mikky/overlay`, `WH_MOUSE_LL` hook, click-through toggle, native menu). `lib/island/island_view.dart` drives the island from the engine. Shader: `app/shaders/island.frag`. Tuning screen: `mikky.exe --tuning` (`lib/tuning/`). Goldens: `app/test/goldens/`.
- GitHub: https://github.com/Gearleur/Mikky (`origin`, branch `main`).
- Visual check: render a prototype with headless Chrome (`chrome --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --screenshot=...`) and compare with a screen capture (GDI captures of the overlay need `CAPTUREBLT`; simulate the mouse with `SendInput`, not `SetCursorPos`).
- `design/prototypes/` — validated HTML prototypes, the visual source of truth. `ile-noir-et-blanc.html` = the validated island (dark "A" + "blanc pur"); `mascotte-variantes.html` = mascot (card "S", without the tail); `ile-trois-noirs.html` = exploration only. `composants.html` = validated UI (buttons, fields, navigation, animations); `ux-a.html` = validated UX of the right-side window (agents home, agent page with Suivi / Chat, input field); shared tokens in `mikky-ui.css`; `design/references/boutons-lanceur.png` = colour and button-shape reference only.

## Decisions (do not re-litigate)
- Flutter everywhere (desktop now, mobile later). Rust only for `mikkyd` later. Windows only for step 1; the app must also run on Linux later, and agents can run on Windows or in WSL, chosen per launch.
- Island = SDF fragment shader (squircle, smooth-min drop and split bubble). Values are in the spec §3.
- Mikky: no mouth, no feet, no pupils; tail only in some states later. Ears carry emotion.
- Dots grid: dark theme only, only while an agent works. Light theme: Apple system colors, no glow, no dots.
- Mikky's transformations are Mikky himself, organic and imperfect, keeping his base shape as much as possible (details in `docs/superpowers/reprise.md` §3).
- Two placements, chosen in the menu: "en haut" (wide island, top center) and "à droite" (right edge, tall like a phone in portrait, text laid out like a phone app, never rotated). Sizes in `IslandMetrics` (engine).

## Environment
- Repo lives on Windows at `C:\Users\alexa\projet\mikky` (moved out of WSL on 2026-09-28; from WSL: `/mnt/c/Users/alexa/projet/mikky`). Windows Flutter at `C:\dev\flutter` (3.47.5) with Visual Studio 2022 C++ workload and Android SDK. Always run `flutter`/`dart` with the Windows install (from WSL: `cmd.exe /c "C:\dev\flutter\bin\flutter.bat ..."`), never the WSL Flutter, on this repo.

## Rules
- Talk to the user in French.
- No telemetry. Secrets in the OS credential store, never on disk or in git.
- Never block Claude Code. Permissions: by default every request goes to the user (Oui / Non in Mikky); an auto-permission mode is allowed only when the user picked it for that launch.
- 0 % CPU when the island is hidden.
- Visual changes must match `design/prototypes/`.
