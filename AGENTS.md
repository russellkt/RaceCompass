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