# AGENTS.md - RaceCompass Context & Handoff

## 1. Project Overview
**Name:** RaceCompass
**Type:** iOS Tactical Sailing Instrument (Regatta Grade)
**Tech Stack:** SwiftUI, CoreMotion (Sensor Fusion), CoreLocation, Combine.
**Hardware Target:** iPhone mounted horizontally (Landscape Locked).
**Goal:** Replace $6,000 tactical hardware (B&G/Velocitek) with an iPhone app that uses raw sensor fusion for Heading, Heel, Speed, and Start Line geometry.

## 2. Current "Gold Master" State
The app is currently split into two distinct modes controllable via a top bar toggle:
1.  **START MODE:** A "Time-to-Burn" start line computer using GPS geometry (Distance to Line Segment) and a Fixed Date Timer.
2.  **RACE MODE:** A high-contrast tactical dashboard with "Infinite Scaling" fonts, Heel Angle (Pitch), SOG, COG, and Layline calculations.

### Key Logic Implemented
* **Sensor Fusion:** Uses `CMMotionManager` to fuse Gyro + Magnetometer for smooth heading (damped by `0.15` factor).
* **Heel Calculation:** Mapped to **Pitch** (not Roll) because the phone is mounted in Landscape (vertical orientation).
* **Start Math:** Calculates distance to the *Line Segment* (clamped to ends) and "Time to Burn" based on potential SOG.
* **Laylines:** Uses a vector intersection algorithm. Includes a "Wind Setup" mode that infers TWD (True Wind Direction) by averaging Starboard and Port tack headings.
* **Timer:** Uses `Date()` (Wall Clock) instead of a simple countdown int to prevent drift.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
