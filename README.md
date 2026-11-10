# pustlivebus

The latest offline schedules, separate fixed routes, departure board, driver trips and admin editor are documented in [Features and setup](docs/FEATURES_AND_SETUP.md). Start there for current behavior, Firebase setup and verification commands.

Flutter application for PUST bus schedules and authorized driver GPS sharing.

## Current features

- Student and driver entry screens with a responsive welcome layout.
- Search by bus name, number, route or stop, including Bengali text.
- All buses and live-only filters, daily departures and countdowns.
- Ordered route stop timelines, including return-route stops.
- Bangladesh time (UTC+6) and Friday holiday schedule selection.
- OpenStreetMap display, driver sign-in and assigned-bus GPS sharing.

Timelines show scheduled stop order, not live progress. Search covers all configured schedules; trip details show today's schedule. Missing holiday schedules are reported explicitly.

## Original implementation roadmap

Trip sessions, selected-bus maps, offline storage, admin forms, in-app timetable reminders and dark mode now have local implementations. Live Firebase permissions/account claims need separate setup. Accurate route-based ETA, background notifications, complete language switching and analytics remain future work; see the current setup guide above.

New live GPS updates require internet. Student GPS is not used as the official bus position. Firebase database rules must enforce driver assignments; those rules were not available for verification here. No remote database records were changed during this development work.

## Verification

Run `flutter analyze` and `flutter test`, then `flutter run -d chrome` for the web app. Validate GPS and foreground tracking on a physical Android device. The supplied conversation and images are references for planned features; confirm the printed schedules before changing production data.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
