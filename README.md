# PUST LiveBus

Flutter application for PUST bus schedules, fixed routes and authorized driver GPS sharing.

## Downloads

- [Latest Android APK — 1.0.3, ARM64](https://github.com/AbdullahAl-Mahmud/pustlivebus/releases/download/v1.0.3/PUST-LiveBus-1.0.3-arm64.apk)
- [Web build — 1.0.3](https://github.com/AbdullahAl-Mahmud/pustlivebus/releases/download/v1.0.3/PUST-LiveBus-Web-1.0.3.zip)
- [Source code — 1.0.3](https://github.com/AbdullahAl-Mahmud/pustlivebus/archive/refs/tags/v1.0.3.zip)
- [All files, including older APKs](https://github.com/AbdullahAl-Mahmud/pustlivebus/releases/tag/v1.0.3)
- [Live website](https://pustlivebus.web.app)

APKs are testing builds signed with the existing debug key. The current APK requires an ARM64 Android device running Android 7.0 or newer. Older APKs are retained for reference; source and web downloads correspond to 1.0.3. [Download details](docs/DOWNLOADS.md).

## Features

- Offline timetables, fixed routes, stop search, favourites and a departure board.
- Authorized driver sign-in, assigned buses, trip start/end and separate map/history pages.
- Driver and student stop progress, next-stop estimates and ordered stop timelines.
- Optional student location for nearby-stop estimates; student GPS is not the official bus position.
- Admin management of buses, routes, stops, schedules and driver assignments.
- Bengali stop names, Bangladesh time, holiday schedules and dark mode.

GPS progress requires fresh driver fixes and a reliable route match. Arrival times are approximate and still require real bus trials. [Features and setup](docs/FEATURES_AND_SETUP.md) and [campus pilot plan](docs/CAMPUS_PILOT_AND_LAUNCH_PLAN_BN.md) explain the current limits.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter build web --release --target lib/main.dart
```

On the original Windows machine, `powershell -NoProfile -File tools/build-apk.ps1 -TargetPlatform android-arm64` produces the testing APK. Configure your own Firebase project and authorized accounts when using another backend. Passwords, service-account keys, signing keys, local database backups, caches and dependencies are excluded from Git.
