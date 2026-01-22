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
