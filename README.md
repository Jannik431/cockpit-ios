# Cockpit

A personal iOS training dashboard that reads sleep, heart rate variability and resting heart rate from Apple Health, compares them against your **own** baseline, and exports clean, versioned weekly reports for training planning.

> **Status:** Phase 1 in progress. The Health Explorer, the Apple Health import and personal baselines are done; the daily card, questionnaire and export are next. See the [roadmap](#roadmap).

## Why

Wearables produce a lot of numbers, but most apps condense them into an opaque “readiness score”. Cockpit takes the opposite approach:

- **Raw deviations instead of a black-box score.** It shows how today's values differ from your personal 7- and 30-day norm. A score will only be added once it has been validated against real data.
- **Clean data for planning.** Instead of screenshots, the app exports a compact weekly report (JSON + Markdown) with explicit data-quality notes.
- **A dataset for a data-science question.** Does a readiness measure predict how you feel the next day better than simple baselines? The app is built so that this can be answered honestly later (stable question IDs, versioned schemas, source per value, missing values stay `null`).

## Features

| | Feature | Status |
|---|---|---|
| 🔍 | **Health Explorer:** shows which Apple Health data actually arrives, from which source and device, how often, at what time of day, and where the gaps are. Exports a Markdown summary. | ✅ Done |
| 📥 | **Apple Health import:** 90 days of history on first launch, then incremental with a 3-day overlap for late syncs. Per wake day: sleep window and stages, raw nightly HRV samples plus their mean, resting heart rate. Workouts are de-duplicated by HealthKit UUID and grouped into suggested sessions. | ✅ Done |
| 📏 | **Personal baselines:** 30-day norm (median of the days *before*, at least 14 values) and 7-day trend. Deviations as a difference in the metric's unit and as a robust z-score (scaled MAD, HRV on log scale) with transparent thresholds. | ✅ Done |
| 📊 | **Daily card:** sleep, HRV and resting heart rate at a glance, with their deviation from the norm | 🚧 Next |
| 📝 | **Wellbeing questionnaire:** fixed core based on the Hooper index plus conditional questions, under 30 seconds a day | 🚧 Next |
| 📤 | **Weekly report:** versioned JSON + Markdown export | 🚧 Next |
| 📅 | Import of the planned training week (CSV), session RPE, configurable rule hints | Phase 2 |

## Design decisions

- **Local-first:** All health data stays on the device (SwiftData). No backend, no cloud, no accounts, no tracking.
- **Read-only HealthKit:** Cockpit never writes to Apple Health.
- **Honest about missing data:** Missing values are shown and exported as `null`, never as `0` and never interpolated. iOS does not reveal whether read access was denied, so “no data” is always labelled as ambiguous.
- **Sources and metrics are never mixed:** Several apps can write the same metric. Each value keeps its source, and only one source per metric is used. HRV is stored as `healthkit_sdnn`, because tracker apps often show RMSSD in their own UI, and the two are not comparable.
- **Local calendar days:** Every metric is stored per local day; a night belongs to the day you wake up. This is tested across daylight-saving changes.
- **Hints, not decisions:** The app makes no medical statements.

## Tech stack

- Swift 6 (approachable concurrency, `MainActor` by default), iOS 17+
- SwiftUI, SwiftData, Swift Charts, HealthKit
- Swift Testing for unit tests; analysis code runs on plain value types, so it is tested with synthetic data and no HealthKit
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): the Xcode project is generated from [`project.yml`](project.yml) and not checked in
- Developed in VS Code with the Swift extension and [SweetPad](https://sweetpad.hyzyla.dev); no third-party dependencies in the app

## Project structure

```
Cockpit/
  App/                 App entry point
  Core/
    Data/              SwiftData models
    Health/            HealthKit access, import, sync
    Metrics/           Pure logic: daily values, baselines, workout grouping (unit-tested)
  Features/
    Dashboard/         Start screen and sync status
    Data/              Stored days for spot checks
    HealthExplorer/    Data source analysis and report
  Resources/           Asset catalog
CockpitTests/          Unit tests (synthetic data only)
scripts/               Test and device deployment scripts
DASHBOARD_APP_SPEC.md  Full specification
```

## Getting started

Requirements: macOS with Xcode 26+, [Homebrew](https://brew.sh).

```bash
brew install xcodegen xcbeautify
xcodegen generate
scripts/test.sh               # build and run unit tests in the simulator
```

To run on an iPhone, set your own `DEVELOPMENT_TEAM` and bundle ID prefix in `project.yml`, connect the phone and run:

```bash
scripts/deploy-device.sh
```

With a free Apple developer account the signature expires after 7 days. Running the script again re-signs the app, and its data is kept.

## Roadmap

1. **Data and daily card:** HealthKit access ✅, Health Explorer ✅, Apple Health import ✅, baselines with tests ✅, daily card, questionnaire core, JSON export
2. **Plan and report:** CSV import of the training week, session RPE, weekly report JSON + Markdown, rule hints
3. **Extensions:** gym logging (e1RM, rest timer / Live Activity), spreadsheet sync via API, charts and analyses

## Privacy

This repository contains no real health data. All test data is synthetic. Exported reports contain sensitive data and are meant to be shared deliberately.
