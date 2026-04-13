# Quick Plan (Flutter)

A Flutter port of [mgifos/quick-plan](https://github.com/mgifos/quick-plan) — a tool to define, import, schedule and share Garmin Connect workouts based on weekly training plans in CSV format.

> **Note:** This project was converted from the original Scala CLI to a Flutter desktop/web app using GitHub Copilot (AI-assisted conversion).

## Platforms

| Platform | Build |
|----------|-------|
| Linux (desktop) | ✅ |
| Windows (desktop) | ✅ |
| Web | ❌ (Garmin API does not like web apps) |
| Android | ✅ |

## Usage

1. Enter your Garmin Connect email and password.
2. Pick a CSV training plan file.
3. Choose a mode:
   - **Import workouts** — uploads all workout definitions from the CSV to Garmin Connect.
   - **Schedule plan** — schedules the weekly plan in your Garmin Connect calendar (requires a start or end date).
   - **Delete workouts** — deletes all workouts from Garmin Connect that share names with those in the CSV.
4. Hit **Run**.

## File format

The file format is a spreadsheet exported to CSV. The 1st row is a heading (define your week days etc.). The 1st column is the week number. Each cell contains one workout definition or a reference to a previously defined workout.

Example 2-week plan:

| Week | Mon | Tue | Wed | Thu | Fri | Sat | Sun |
|------|-----|-----|-----|-----|-----|-----|-----|
| 1 | `running: run-fast - warmup: 10:00 @ z2 - repeat: 3 - run: 1.5km @ 5:10-4:40 - recover: 500m @ z2 - cooldown: 05:00` | rest | rest | run-fast | rest | rest | rest |
| 2 | run-fast | `cycling: cycle-wo - bike: 15 km @ 20.0-30kph` | rest | run-fast | rest | rest | cycle-wo |

A full example plan: [80K ultra training plan](https://docs.google.com/spreadsheets/d/1b1ZzrAFrjd-kvPq11zlbE2bWn2IQmUy0lBqIOFjqbwk/edit?usp=sharing)

## Workout notation

```
<workout>   := <header>(<newline><step>)+
<header>    := [running | cycling | custom]: <name>
<step>      := <indent>- <step-def>
<step-def>  := <simple-step> | <repetition-step>

<simple-step>      := (warmup | cooldown | run | bike | go | recover): <duration> [@ <target>]
<repetition-step>  := repeat: <count>(<newline><step>)+

<duration>  := <distance-duration> | <time-duration> | lap-button
<distance-duration> := <number> (km | m | mi)
<time-duration>     := <minutes>:<seconds>

<target>    := <zone-target> | <pace-target> | <hr-target> | <speed-target> | <power-target> | <cadence-target>
<zone-target>     := z[1-6]
<pace-target>     := <pace> - <pace> (mpk | mpm)?
<hr-target>       := \d{1,3} - \d{1,3} bpm
<power-target>    := \d{1,3} - \d{1,3} W
<cadence-target>  := \d{1,3} - \d{1,3} rpm
<speed-target>    := <kph-speed> - <kph-speed> (kph | mph)?
```

Example workout:

```
running: 15k, 3x3.2k @HMP
- warmup: 2km @z2
- repeat: 3
  - run: 3200m @ 5:05-4:50
  - recover: 800m @z2
- run: 1km @z2
- cooldown: lap-button
```

## Measurement system

Metric is the default. Imperial can be selected in the Options section of the UI. Units can also be specified explicitly in the workout notation:

- Distance: `km` vs `mi`
- Speed: `kph` vs `mph`
- Pace: `mpk` vs `mpm`

## Building

```sh
# Linux
flutter build linux --release

# Windows
flutter build windows --release

# Android
flutter build apk --release
```

## Known issues

- Use Google Sheets or LibreOffice Calc to edit CSV files. Both use LF for internal line breaks inside cells. The CSV parser does not handle CR-only line breaks inside quoted fields.

## Credits

Based on [mgifos/quick-plan](https://github.com/mgifos/quick-plan) by Marko Gifos (Scala, CLI).
This Flutter port was created with the assistance of GitHub Copilot.
