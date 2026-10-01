# Pace

A small running app for iPhone. Evidence-based training that adapts to your real life.

Pace follows a structured run/walk program to 5K and adjusts it to the weeks you actually have. Miss a few sessions and the plan adapts conservatively, then tells you exactly what changed and why. The program adapts to you; you're not failing the program.

## Principles

- **Private by default.** No account, no backend, no ads, no tracking, no analytics. Your runs stay on your device and the app works fully offline.
- **Structured programs, not generated ones.** Training plans are hand-built from running research (gradual progression, run/walk for beginners, deload weeks) and stored as plain data.
- **Adaptation you can trust.** A deterministic engine decides what may change: move a session, repeat a week, ease next week's volume, hold progression. It never quietly adds volume beyond what the program prescribes.
- **Made to glance at mid-run.** Big numbers, high contrast, a dark run screen, and audio cues at every interval switch that work on silent and with the phone locked.

## Features

- Couch-to-5K: a 9-week run/walk program
- Guided runs with interval countdowns, sound and voice cues, GPS distance and route
- Free runs, switching between run and walk yourself
- Weekly plan check that adapts to missed or shortened weeks, with a plain explanation
- Run recaps with per-interval pace and a route map
- Dark and light appearance

## Building

Requires Xcode with the iOS 17+ SDK. No dependencies, no package manager.

```bash
git clone https://github.com/rktmatt/Pace.git
cd Pace
open Pace.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project Pace.xcodeproj -scheme Pace -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild test -project Pace.xcodeproj -scheme Pace -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

To run on your own device, select your team under *Signing & Capabilities* and change the bundle identifier.

## Architecture

SwiftUI and SwiftData, grouped by role under `Pace/Sources`:

- `Domain/`: program definitions (static data) and persisted user state
- `Programs/`: bundled training programs and scheduling
- `Engine/`: the deterministic adaptation pipeline (analyze the week → decide → apply)
- `Location/`: GPS tracking, the interval timer and sound cues
- `Views/`: screens

See [CLAUDE.md](CLAUDE.md) for a more detailed tour.

## Support

Pace is free. If it helped you get out the door, you can [buy me a coffee on Ko-fi](https://ko-fi.com/rktmatt).

## License

[MIT](LICENSE)
