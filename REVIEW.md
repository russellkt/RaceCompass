# RaceCompass Code Review

## 1. Sailor's Perspective ⛵️

As a sailor, the functionality provided is impressive for a standalone app. It covers the "Big 3" needed for starting: **Distance**, **Time**, and **Bias**.

### ✅ What works well
*   **Landscape "Pitch as Heel":** Smart decision. Most mounts are landscape. Using pitch is the correct axis.
*   **Wall Clock Timer:** Using `Date()` instead of a countdown integer is the pro move. It prevents timer drift and allows for "Sync to nearest minute" which is essential when you miss the gun.
*   **Wind Setup:** Averaging Port and Starboard headings to find TWD (True Wind Direction) is the standard tactical solution when you don't have wind instruments.
*   **Start Coaching:** The "REACH", "TURN BACK", "GO" logic is sophisticated. It essentially replaces a dedicated tactician calling the start.

### ⚠️ Areas for Improvement (Sailing Logic)

#### 1. Magnetic Variation (Critical)
The app currently mixes **Magnetic** and **True** headings.
*   **Heading:** `xMagneticNorthZVertical` returns **Magnetic North**.
*   **GPS (COG/SOG):** CoreLocation usually reports Course Over Ground relative to **True North** (unless explicitly configured or calculated).
*   **The Problem:** If you compare `Heading` (Magnetic) with `COG` (True) or use `GPS Coordinates` (True Grid) with `Wind Direction` (Magnetic), your math will be off by the local magnetic variation (which can be 15°+ in places like Seattle or UK).
*   **Fix:** Either convert everything to True (using `CLLocation.course` and looking up variation) or ensure COG is converted to Magnetic before doing vector math with Heading.

#### 2. Damping Factor
`displayHeading` uses a hardcoded damping factor of `0.15`.
*   **Issue:** While smooth, this might be too laggy for the pre-start "dance" where you need instant feedback on rate-of-turn.
*   **Suggestion:** Use **Dynamic Damping**.
    *   If `rateOfTurn` is high (> 5°/sec), lower damping (e.g., `0.5`) for responsiveness.
    *   If sailing straight, increase damping (e.g., `0.10`) for stability.

#### 3. GPS Latency (SOG)
The start math relies heavily on `SOG` (Speed Over Ground) from GPS.
*   **Issue:** iPhone GPS updates at 1Hz (best case) and often has a 1-2 second lag.
*   **Consequence:** "Time to Burn" might be optimistic. If you accelerate, the app won't know for 2 seconds.
*   **Suggestion:** Add a "safety buffer" option in settings (e.g., "Assume I'm 0.5kts faster than GPS says" or just subtract 2 seconds from Time-to-Burn).

---

## 2. Developer's Perspective 👨‍💻

The code is clean and readable, but the architecture is starting to show "growing pains" as features are added.

### 🏗 Architecture
**Current State:** `CompassViewModel` is a "God Object" (Massive View Model).
It handles:
1.  Sensor Fusion (CoreMotion)
2.  Location Services (CoreLocation)
3.  Race Logic (Start line math, VMC)
4.  Timer Logic
5.  View State

**Risks:**
*   **Testability:** You cannot unit test the "Start Logic" without mocking `CMMotionManager` and `CLLocationManager`, which are hard-coded in `init()`.
*   **Maintainability:** The file is becoming long and difficult to navigate.

**Recommendation:** Refactor into services.
*   `LocationService`: Wraps CLLocationManager, publishes location/heading.
*   `SensorService`: Wraps CMMotionManager, publishes filtered heading/heel.
*   `RaceComputer`: Pure logic class. Takes `Location`, `Time`, `Wind` inputs -> Returns `StartPhase`, `TimeToBurn`. (Easily unit testable!).
*   `TimerService`: Handles the clock.

### ⚡️ Performance & Concurrency
*   **Main Thread:** The sensor updates (20Hz) are processed on the Main Thread. Currently, the math is light, so it's fine.
*   **View Updates:** `CompassViewModel` is an `ObservableObject`. Every time *any* published property changes (20 times a second), SwiftUI re-evaluates the view body.
*   **Optimization:** Ensure `RaceView` and `StartView` components are efficient. If the view hierarchy grows, you might see battery drain or stutter.

### 🛠 Code Quality
*   **Hardcoded Constants:** Values like `1.94384` (knots conversion), `0.15` (damping), and `111139.0` (meters/degree) are scattered. Move these to a `Constants` struct.
*   **Coordinate Math:** You are manually calculating distance using `cos(lat)`.
    *   `CLLocation` has a built-in `distance(from:)` method which is more accurate (Great Circle).
    *   For the "Intersection Time" logic, you are projecting to a flat plane. This is acceptable for start lines (< 1km), but be aware of the limitation.

### 🛡 Error Handling
*   `locationManager(_:didUpdateLocations:)` assumes valid data.
*   `CMMotionManager` availability is checked, but errors during updates aren't handled/logged.

## Summary
Great foundation. The app is definitely usable in its current state ("Regatta Grade" logic is there). The next steps should focus on **Separation of Concerns** (breaking up the ViewModel) and addressing the **Magnetic Variation** issue before trusted usage in high-stakes races.
