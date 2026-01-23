# RaceCompass Development Session - January 22, 2026

## Overview
This session added GPX waypoint import, course setup, VMC calculations, and improved cockpit visibility for the RaceCompass sailing instrument app.

---

## Features Implemented

### 1. GPX Waypoint Import System

**Files Created:**
- `Models/Waypoint.swift` - Data model for waypoints and course setup
- `Services/GPXParser.swift` - XML parser for GPX files
- `Services/WaypointStore.swift` - Persistence layer (JSON to Documents directory)
- `Views/CourseSetupView.swift` - Course configuration UI

**Capabilities:**
- Import GPX files via iOS Files picker
- Waypoints persist across app restarts
- Duplicate detection by name and location

---

### 2. Flexible Course Setup

**Course Structure:**
- **Port Start** - Pin end of start line (select waypoint)
- **Stbd Start (RCB)** - Either select waypoint OR auto-calculate 50' perpendicular to first mark bearing
- **Course Marks** - Add unlimited marks in order (swipe to delete)
- **End Pin** - Finish mark

**Start Line Calculation:**
- Auto-calculates boat end position 50' perpendicular (to starboard) of the Port Start → First Mark bearing
- Can override with manual waypoint selection for RC boat position

---

### 3. Add Waypoint from GPS

- Green "Add Mark at Current Position" button in Course Setup
- Prompts for waypoint name
- Creates waypoint at current GPS coordinates
- Useful for marking RC boat or temporary marks on the water

---

### 4. VMC (Velocity Made Good on Course)

**Formula:** `VMC = SOG × cos(COG - bearing to target)`

**Pre-Start Mode:**
- VMC targets midpoint of start line
- Displayed in stats row: DIST | VMC | BURN

**Race Mode:**
- VMC targets current course mark
- Bearing to mark displayed
- Distance to mark displayed
- Color-coded: green (positive VMC), red (negative VMC)

---

### 5. Automatic Leg Advancement

**Auto-advance triggers:**
1. **Start**: When timer goes negative (secondsToStart < 0), advances from leg 0 to leg 1
2. **Mark Rounding**: When within 100 feet (30.48m) of current mark, advances to next leg

**Manual override:** MARK button still available

---

### 6. Cockpit-Optimized Race View Layout

Redesigned for readability from 3-10 feet away:

```
┌──────────────┬──────────────────┬──────────────┐
│     BRG      │     LAYLINE      │     DIST     │
│    (22%)     │                  │     (18%)    │
├──────────────┤                  ├──────────────┤
│     VMC      │      HDG         │     SOG      │
│    (22%)     │     (45%)        │     (18%)    │
│   colored    │                  │              │
│              │                  │              │
│     COG      │     HEEL         │   [MK btn]   │
└──────────────┴──────────────────┴──────────────┘
```

**Font sizes (% of screen height):**
- Heading: 45% - massive, center focus
- BRG/VMC: 22% each - very readable
- DIST/SOG: 18% each - clearly visible
- COG/HEEL: smaller supporting data

---

## Button Reference

### Start View
| Button | Location | Purpose |
|--------|----------|---------|
| SET STB / SET PORT | Top | Wind tack references for layline calc |
| SET WIND | Top | Set true wind direction manually |
| PORT button | Bottom | GPS ping pin end of start line |
| STBD button | Bottom | GPS ping RC boat end |
| COURSE button | Bottom | Opens waypoint-based course setup |
| 5m / 1m | Bottom | Sync timer to 5 or 1 minute |

### Race View
| Button | Location | Purpose |
|--------|----------|---------|
| MK# | Bottom right | Manually advance to next leg |

---

## Data Flow

```
WaypointStore (persisted)
    ├── waypoints: [Waypoint]      → Available marks from GPX
    ├── courseSetup: CourseSetup   → Selected course configuration
    │       ├── portStartId
    │       ├── stbdStartId (optional)
    │       ├── markIds: [UUID]
    │       └── endPinId
    │
    └── Computed:
        ├── portStart → CLLocation
        ├── stbdStartLocation() → CLLocation (manual or calculated)
        └── courseMarks → [Waypoint]

CompassViewModel
    ├── pinEnd / boatEnd → Start line endpoints
    ├── courseMarks: [CLLocation] → Race marks
    ├── currentLeg: Int → 0=prestart, 1+=racing
    ├── nextMarkBearing → Bearing to target
    ├── vmcToMark → VMC in knots
    └── distanceToMark → Distance in meters
```

---

## File Structure

```
RaceCompass/
├── ContentView.swift          # Main app, CompassViewModel, RaceView, StartView
├── Models/
│   └── Waypoint.swift         # Waypoint, CourseSetup structs
├── Services/
│   ├── GPXParser.swift        # XMLParser for GPX import
│   └── WaypointStore.swift    # Persistence, calculations
└── Views/
    └── CourseSetupView.swift  # Course configuration modal
```

---

## Test Data

`fyc_marks.gpx` contains 9 Fairhope Yacht Club racing marks:
- FYC-N, FYCNW, FYC-W, FYCSW, FYC-S, FYCSE, FYC-E, FYCNE, FYC-X (center)

---

## Future Considerations

- Crossed start line detection (geometric line crossing vs timer-based)
- Course templates (windward-leeward, triangle, etc.)
- Mark rounding direction indicators
- Integration with actual wind instruments

---

# RaceCompass Development Session - January 23, 2026

## Overview
This session merged PR #1 (Themes, Haptics, Settings), fixed issues from that merge, and significantly improved the prestart reach maneuver coaching system with physics-based timing and proper sailing geometry.

---

## PR #1 Merge: Themes, Haptics, and Settings

**New Files:**
- `Services/ThemeManager.swift` - Day, Night (red), High Contrast themes
- `Services/HapticManager.swift` - Tactile feedback for phase changes and gun
- `Views/SettingsView.swift` - Configure themes, haptics, and boat speed params

**Capabilities:**
- Theme switching persisted via @AppStorage
- Haptic feedback on start phase transitions and gun (0:00)
- Adjustable target speed, acceleration time, and safety buffer

---

## Post-Merge Fixes

### Minor Code Quality Fixes
- Removed redundant `updateTheme()` call (didSet already handles it)
- Used shared `HapticManager.enabledKey` constant to prevent key mismatch
- Updated deprecated `onChange(of:perform:)` to iOS 17+ signature
- Added missing `import Combine` to ThemeManager

### High Contrast Theme Fix
- Changed `warning` color from white to gray
- SET STB/PORT buttons now visually change (gray → white) when set

---

## Prestart Coaching Overhaul

### Target Distance Now Locks on REACH Entry
**Problem:** Target distance was recalculating every tick, counting down even when stationary.
**Fix:** Lock `targetReachDistance` when entering REACH phase, reset when exiting.

### Math-Based Timing (No Magic Numbers)
All timing derived from physics:
```swift
maneuverTime = (distance / reachSpeed) + (distance / returnSpeed) + accelTime + buffer
reachStartTime = maneuverTime + 10s margin
```

### Reach Course: Parallel to Line (Not Beam Reach)
**Before:** Suggested 90° to wind (beam reach)
**After:** Suggested course parallel to start line (boat-to-pin or pin-to-boat bearing)

### Distance Tracking Along Line
- Added `distanceAlongLine` - tracks travel from reach start position
- Added `reachStartPosition` - recorded when entering REACH phase
- TURN BACK triggers when `distanceAlongLine >= targetReachDistance * 0.9`

### 45° Boundary Limits
- Don't sail past 45° angle from line ends
- On starboard tack: boundary is 45° past pin
- On port tack: boundary is 45° past boat
- Shows "BOUNDARY" warning if exceeded

### SLOW TO Isolated to Approach Phase
- Only triggers when `isApproaching` (VMC toward line > 0.1 kt)
- Cannot appear during REACH or TURN BACK phases

---

## Prestart Phase Timeline

| Time | Phase | Display |
|------|-------|---------|
| > 150s | HOLD | "PREP" |
| 150s → ~140s | HOLD | "HOLD Xs" (countdown to reach) |
| ~140s | REACH | "REACH 270°" with "Xm / Xm" progress |
| Hit target distance | TURN BACK | "TURN BACK" with "STEER XXX° TO LINE" |
| Approaching | HOLD | "HOLD Xs" with "LINE XXX° • VMC X.X kt" |
| Too fast | SLOW TO | "SLOW TO X.Xkt" |
| < 15s | BUILD/GO | "BUILD SPEED" / "GO!" |

---

## New Published Properties

```swift
@Published var bearingToLine: Double      // Bearing to closest point on line
@Published var distanceAlongLine: Double  // Distance traveled from reach start
@Published var pastBoundary: Bool         // True if past 45° boundary
private var reachStartPosition: CLLocation? // Position when REACH started
```

---

## Display Updates

### REACH Phase
- Shows progress: "145m / 180m" (distance traveled / target)

### TURN BACK Phase
- Shows: "STEER 270° TO LINE" prominently

### HOLD/SLOW TO (Approaching)
- Shows: "LINE 270° • VMC 3.2 kt"

### Timer Remains Dominant
- 25% of screen height
- Largest font, always visible
- All other info supports getting to line at zero

---

## Commits Today

1. `2dd74cd` - Fix minor issues from PR #1 themes/haptics merge
2. `82feec3` - Fix High Contrast theme button state visibility
3. `fe36f5d` - Lock target reach distance when entering REACH phase
4. `bccaf82` - Improve reach maneuver timing and isolate SLOW TO
5. `4b0ecad` - Align prestart phases with sailing sequence timeline
6. `b337967` - Reach parallel to line with 45° boundary limits
7. `ead3321` - Show bearing to line during approach phases

---

## Key Insight: The Reach Maneuver

The "reach out and reach in" prestart strategy:
1. Sail **parallel** to the line to a target distance
2. Target distance calculated from boat speed settings
3. Turn back when reaching target OR hitting 45° boundary
4. Sail back toward line on reciprocal course
5. Bearing to line displayed to guide return heading
6. Timer is king - everything else supports hitting zero at the line
