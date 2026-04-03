# RaceCompass

A regatta-grade tactical sailing instrument for iPhone, designed to replace dedicated hardware systems that cost $500+ — and gives you something none of them offer: real-time training and strategy.

Mount your iPhone horizontally in the cockpit and get real-time heading, heel angle, speed, start line geometry, and coaching — all from the sensors already in your pocket.

## Features

### Start Mode — Time-to-Burn Start Line Computer
- **Start line geometry** — GPS-based distance to the line with endpoint clamping
- **Countdown timer** — Wall-clock synced to prevent drift, with elapsed time after start
- **Coaching state machine** — Phase-based tactical prompts (REACH, TURN BACK, HOLD, BUILD, GO) driven by VMC, distance, and time remaining
- **Wind setup** — Infer True Wind Direction by averaging starboard and port tack headings
- **Configurable acceleration** — Set target speed, time to accelerate, and reaching speed multiplier for accurate time-to-burn predictions

### Race Mode — Tactical Dashboard
- **Heading** — Sensor-fused gyro + magnetometer with True North correction
- **Heel angle** — Mapped to pitch for landscape-mounted phones
- **SOG / COG** — GPS-based speed and course over ground
- **Waypoint navigation** — Bearing, distance, and VMC to next mark
- **Layline calculations** — Vector intersection algorithm for tack timing
- **Course management** — Import marks via GPX files, configure start/finish lines

### Display
- High-contrast, auto-scaling fonts optimized for cockpit visibility
- Three themes: Day, Night (red/black for night vision), High Contrast
- Landscape-locked layout sized for horizontal phone mounts

## Tech Stack

- **SwiftUI** — UI framework
- **CoreMotion** — Gyro + magnetometer sensor fusion (heading, heel)
- **CoreLocation** — GPS position, SOG, COG, magnetic declination
- **Combine** — Reactive data pipeline at 10Hz update rate

## Building

Open `RaceCompass.xcodeproj` in Xcode and build to a physical iPhone. The app requires device sensors (GPS, gyro, magnetometer) and will not function in the simulator.

## License

This project is provided as-is for personal and educational use.
