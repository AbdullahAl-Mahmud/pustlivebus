# PUST LiveBus features and setup

This update adds offline schedules and a separate fixed route browser to the existing Flutter app. It also adds a departure board, device favourites, date selection, app reminders, driver trip sessions and a transport administrator editor. Remote configuration is kept separate from the bundled reference timetable.

## Public website

The web app is deployed at **https://pustlivebus.web.app**. Hosting initially pointed at `public/`, which contained Firebase's default welcome page. `firebase.json` now serves `build/web`, keeps the single-page-app rewrite and sends `Cache-Control: no-cache`. The corrected release was deployed to project `pustlivebus`; its public index, app manifest and offline worker were checked over HTTPS.

For later updates, bump the cache version in `web/offline_service_worker.js`, run `flutter build web --release`, then `firebase deploy --only hosting --project pustlivebus`. Hosting setup is already complete; there is no need to rerun `firebase init hosting`. If initialization is run again, preserve `public: build/web` and decline overwriting the app's `index.html`. A hard refresh can clear an older cached landing page. Future offline-worker updates activate after old app tabs close.

## Supplied logo and visual theme

The supplied `pust-mobility-white.png` and `pust-mobility-transparent.png` are copied unchanged into `assets/branding/`. The welcome screen uses the transparent logo as a faint background watermark in light and dark modes, behind the centered welcome text and buttons. It has no separate artwork/poster card. The watermark ignores taps and is excluded from accessibility announcements. A smaller foreground logo identifies the app; the welcome/student header also includes a small logo.

`lib/theme/app_brand.dart` centralizes the bus-maroon, road-charcoal, warm stone and cream palette. Buttons, cards, app bars, navigation and route lines follow this palette in light/dark modes. Green remains available for the existing live-GPS status indication.

The browser favicon, install icon and Android launcher resource use the supplied white-background artwork. Its original 1254×1254 size is accurately declared in the web manifest. An Android launcher change requires a new native build/install and is not applied by hot reload. The Android release APK has now built successfully; the supplied Flutter logo assets were checked inside it, but launcher appearance on a physical phone is not yet tested. Existing iOS/macOS/Windows native launcher icon sets are unchanged. Both in-app logo files and the browser icon are part of the release web offline shell (cache version 4).

## Student location and approximate arrivals

Bus details and the map now include **আমার স্টপে কখন আসবে?**. A dedicated planner is also available from **Routes → expand a route → স্টপের আনুমানিক সময়** and opens without loading map tiles. Tap **আমার অবস্থান ব্যবহার করুন** to explicitly request a single current phone location. The nearest stop on the selected fixed route is suggested. Students can change bus, route or stop manually, including choosing a particular occurrence on the return journey. Location permission is optional; manual stop selection and offline planning continue without it.

The student's fix stays in the open page's memory. It is not uploaded, persisted, used as the official bus location, or watched in the background. **অবস্থান মুছুন** clears it. After two minutes, it is treated as old and stops contributing to distances until refreshed. The map shows the fresh fix with a blue person marker. GPS/service disabled, permission denial, timeouts and inaccurate fixes have recoverable messages.

Two distance labels have different meanings: student-to-stop and bus-to-student are straight-line distances; bus-to-stop is along the connected-stop sketch. These are not road-routing or walking distances. The estimate is for a bus reaching a route stop, not driving to an arbitrary passenger location. If the closest stop is far away, the app asks the student to review the route/stop choice.

Fresh driver GPS (under 30 seconds old, with known accuracy up to 100 metres) can provide an approximate remaining time when its route segment is unambiguous. Stops passed on that occurrence are identified. Overlapping outward/return segments, an off-route fix, missing coordinates or an uncertain route suppress that live estimate. Old GPS never produces a live countdown. Current speed is not simply divided into straight-line distance: a stopped bus would otherwise produce nonsensical results.

Offline or without a usable driver fix, the card shows **প্রাথমিক যাত্রা পরিকল্পনা · live countdown নয়**. It estimates elapsed travel after departure and a possible clock time if the scheduled departure actually happens on time. An expandable list shows every stop's planning time. Midnight rollover is labelled. Routes with missing coordinates deliberately leave later estimates unavailable.

Initial assumptions are explicitly displayed: a configurable 10–40 km/h typical speed (default 20), connected-stop distance multiplied by 1.25, and 30 seconds per intermediate stop. These are uncalibrated planning assumptions, not verified road lengths, traffic information, official arrival times or a trained ETA model. Displayed ranges are broad heuristics (roughly 0.7–1.5 times the estimate plus a small buffer), not validated statistical confidence intervals. Field calibration and a real road shape are needed before relying on the times.

### Learning from actual usage

While the student app is open and receiving fresh **driver** fixes, it can learn travel durations between adjacent stops. This does not collect the student's own travel history. A journey can establish direction at an unambiguous stop; repeated stop locations cannot establish direction by themselves. The learner requires driver accuracy within 60 metres, ignores duplicate/out-of-order fixes, resets across gaps over 45 seconds, and rejects implausible samples. Geofence timing is approximate.

Only per-route/per-leg duration samples are retained locally, capped at 12 per leg and 60 route profiles. No driver trip ID, raw movement trail or student GPS is saved in these profiles. At least three samples are required before using a leg's median travel time. A changed stop order or coordinates changes the profile signature, preventing reuse of an old route's timings. Remaining legs keep the explicit planning assumptions. Each estimate shows how many legs use learned timings. Samples survive restart and can be cleared in **Offline → Arrival time শেখার তথ্য**.

Learning is **per device/browser**, not a fleet-wide shared training dataset. Opening the app midway through a trip may give no direction evidence, especially on overlapping return routes. A future shared estimator should aggregate approved driver trip measurements server-side and publish anonymous route statistics, with adequate sample coverage and validation; it should not let passenger GPS overwrite bus positions.

## Ten-driver planning roster

Open **Transport admin → Drivers → ১০ জন driver-এর roster**. There are ten empty planning slots for names, planned buses/standby and an optional existing Firebase User UID. A named draft can be saved without a login account. It is stored on that browser/device only, is not cloud-shared and does not grant tracking access.

No new driver Authentication accounts were created, since the ten drivers' account details have not been supplied. The owner must create real accounts first. Once a UID and actual online bus are available, **Online assignment করুন** opens the existing assignment editor for review and Save. It validates active bus references and checks existing old/new assignments for open trips. A reference-copy bus ID is not automatically imported into the online database. Multiple drivers can be assigned to one bus for shifts/standby; the per-bus trip lease still permits only one open trip at a time. A draft planned shift is not a server-enforced shift schedule.

The ten slots are a planning target, not a limit that would silently remove any existing driver accounts. Driver account creation, rules deployment and shared roster synchronization remain separate actions.

## Student experience

Use **I am a Student**, then the four tabs:

| Tab | Available features |
| --- | --- |
| Buses | Bengali/English search, Bengali numeral search, live filter, favourites, next scheduled departure, trip details and stop timelines |
| Routes | All fixed routes independently of today's schedule, ordered stop lists, associated buses and a map sketch |
| Board | Scheduled departures filtered by a chosen stop and date; regular and holiday views |
| Offline | Download status, included reference copy, save again, reminders and dark mode |

The initial reference contains 8 buses, 6 routes, 22 stop records and 28 scheduled departures, including 4 holiday departures. These records are a transcription of the supplied images and coordinate list, not an independently confirmed transport notice. The reference notes the printed effective date of 31 October 2026. Confirm it with the transport office. Return stop lists expand the notice's “same route” wording. Missing stop coordinates are left empty.

The board shows departure from the route origin, not an invented arrival time at every stop. Friday is the default holiday; `calendar/YYYY-MM-DD` can override a particular date as `regular` or `holiday`.

## Offline behavior

The included JSON is bundled with the application, so an installed Android app can open schedules and route stops on its first offline launch. A coherent downloaded copy of buses, stops, routes and schedules is automatically saved using device storage. A partial initial download cannot replace the full local catalogue. The optional calendar is also saved when available. Downloaded data and the reference copy are separate; a reference bus ID is never mapped to a remote GPS position.

Favourites, dark mode and reminders persist on the same device/browser profile. Storage failures are reported in the interface. Live GPS is never persisted as a live offline position. Old positions remaining in the current session are labelled as last known when the connection is lost.

A **release web build** includes a service worker that caches the application, local rendering engine, Bengali font and reference data after a complete first visit. It can reopen offline on HTTPS or localhost after this installation finishes. The Flutter development server is for development and does not provide the same offline reopening guarantee. Clearing site data, private browsing restrictions, browser storage eviction or uninstalling the app can remove saved data.

Map tiles and fresh driver updates still require internet. The service worker caches only the app's own origin, never Firebase or remote OpenStreetMap tiles. Stop lists remain available without a map.

When publishing a changed web build, bump the cache version in `web/offline_service_worker.js`. The next worker activates after old app pages close, keeping an app shell together during upgrades.

## Reminders

Trip details include a 10-minute departure reminder. The reminder uses Bangladesh time and is stored locally. It appears inside the open app, including while offline. A missed reminder is labelled as a passed departure after reopening. These are **not operating-system background notifications**. Push/background arrival alerts remain a separate implementation task.

## Driver trips

An existing Firebase Authentication driver account must have `drivers/{uid}` with an active bus assignment. The route picker uses routes appearing in that bus's remote schedules. Reference-only IDs are never written to Firebase.

Starting a trip obtains a GPS fix, acquires a per-bus active session, creates trip history, registers disconnect handling and starts publishing. A transaction prevents a second session from replacing an open trip. Ending a trip closes history, marks location sharing off and releases the active session. A previous unclosed trip can be closed before starting again. Location publishing stops on a detected disconnection; reconnection requires closing the open trip and starting a new one.

Each fix includes collection time, server timestamp, accuracy, speed, route ID, trip ID and driver UID. Low-accuracy or mocked fixes are skipped by the client. The proposed server rules reject stale fixes, invalid coordinates, mismatched sessions and writes by unassigned users. These checks do not prove that an authorized phone is physically on the bus; phone custody and field testing are still required.

Android uses a foreground tracking notification while a trip is active. Browser tracking is for foreground testing and is subject to browser suspension. Validate screen-off behavior, permissions, GPS accuracy and battery handling on a physical Android phone before a real pilot.

## Firebase configuration required for driver and admin features

**No production database records were changed.** On 31 October 2026, the owner explicitly authorized granting administrator access to the supplied Firebase Authentication UID. Its `admin: true` custom claim was applied and read back successfully. On 1 November 2026, a driver-save failure was traced to the old deployed rules: they allowed only each driver's own assignment read, no administrator listing/writes, and no active-trip checks. After explicit owner approval, the tested `database.rules.json` was deployed and read back to verify an exact match. Previous rules and a deployment receipt are saved in ignored `artifacts/firebase-*.json` files.

1. Back up existing Realtime Database data and rules.
2. Review `database.rules.json` and run its tests in a working local emulator before deploying it. It provides public timetable/latest-location reads, private assignments and trip history, assigned-driver writes and administrator-only catalogue edits. It requires collection timestamps on new live records, so older driver clients must be upgraded at the same time.
3. Have the project owner grant `admin: true` as a Firebase Authentication **custom claim** on the intended administrator account using a trusted Admin SDK environment. A client-side role field is not an administrator grant. Do not put service account secrets in Flutter assets or this repository.
4. Open **Transport admin** from the welcome screen, then sign in with that account. The forms can add/edit/archive buses, stops, ordered routes, schedules and driver assignments, and set date exceptions. Driver accounts must already exist in Firebase Authentication. The editor does not create authentication accounts or grant itself access.
5. Assign a driver account ID to an active bus and configure that bus's schedules/routes. Assignment changes and bus deactivation are blocked while a trip is open.
6. Test one driver phone and one student device before adding the remaining buses.

The production Flutter Firebase options remain unchanged. The emulator config uses **demo-pustlivebus** only. `firebase.emulator.json` points at the tested rules; the existing production `firebase.json` has not been altered to deploy them automatically. The authorized deployment used `tools/firebase-tests/deploy-database-rules.cjs`, which defaults to a read-only plan and requires an expected backup plus `--apply` to deploy. It checks for concurrent rule changes, takes another backup and verifies the result. Never use `--apply` without explicit owner approval.

### Administrator sign-in troubleshooting

“This account does not have administrator access” means the password sign-in succeeded but the refreshed Firebase token has no boolean `admin: true` claim. After the project owner grants it, sign in again (the app forces token refresh). Every newly opened admin screen requires email/password sign-in even when Firebase has restored an earlier session. The panel includes Sign out, which closes its data listeners, clears its displayed records and signs out of Firebase. Adding an `admin` field in Realtime Database does not grant this permission.

The owner setup helper at `tools/firebase-tests/admin-access.cjs` uses the existing Firebase CLI project login. Install that directory's dependencies with `npm ci` first if needed. From the project root, `node tools/firebase-tests/admin-access.cjs --uid=USER_UID` only checks the specified account. Adding `--apply` grants `admin: true`, preserves its other claims and reads the account back to verify it. Run that option only after explicit owner authorization. It never asks for the user's password or prints credentials. It targets `pustlivebus` only and does not modify database rules or timetable data.

Sign-in now displays distinct authentication error codes and does not depend on the Realtime Database connection. Database editing still requires its connection and server permissions. Administrator access on the account does not by itself deploy database rules.

After a permissions update, refresh the page and sign in to the admin panel again so listeners previously rejected by the server can reconnect. Adding a driver assignment requires the real existing Authentication UID and an active online bus. The ten-slot draft roster does not create Authentication accounts. Existing APK 1.0.0 uses the new server permissions without reinstalling; older driver clients that lack trip/session fields must upgrade.

## Verification commands

For the arrival/roster update, `flutter analyze` reported no issues and all 25 Flutter tests passed, including permission denial, location privacy, stale GPS, loop ambiguity, learning, offline fixed-route planning, future-date separation and roster persistence. The release web build completed. Installed Chrome checks exercise student geolocation, arrival planning, tab navigation and offline page reopening. Mobile and desktop screenshots were inspected. On 1 November 2026 the Android release build also succeeded. APK signature verification, 16 KB native-library alignment and packaged offline-catalog/logo integrity checks passed. All 10 Firebase emulator rules tests now pass, including the exact administrator driver read/check/save sequence and rejection of invalid references/non-admin writes. Physical-phone GPS testing remains unexecuted.

From the project root:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter build web --no-pub
flutter build apk --debug --no-pub
```

For this Windows machine, `powershell -File .\tools\build-apk.ps1` uses a project-local temporary directory to avoid the Java socket-path failure. Run `flutter pub get` first when dependencies change. The script restores its process environment afterward and places the APK plus SHA-256 file in `artifacts/`. It uses Android Studio's Java when available. Version changes must also be reflected in Flutter's generated Android configuration; the helper checks the packaged version before naming the delivery file.

From `tools/firebase-tests`:

```powershell
npm ci
npm run test:rules
```

The rules tests cover public read-only access, student write rejection, assigned-driver access, GPS validation, concurrent sessions, history completion, obsolete session updates, admin claims and reassignment during an open trip. They must run against the local emulator and refuse to start without its environment variable.

The Windows environment previously reported `Unable to establish loopback connection` / `Invalid argument: connect` inside Java's selector initialization. Changing Java runtimes alone did not fix it. The APK build and database emulator tests succeeded after setting `TEMP`, `TMP`, `java.io.tmpdir` and `jdk.net.unixdomain.tmpdir` to the project's `.build-temp` directory for each process. The emulator run also used `FIREBASE_EMULATORS_PATH` pointing to `tools/firebase-tests/.emulators`. Its rules compiler caught a boolean expression that has now been corrected and covered by the passing tests.

The delivered `artifacts/PUST-LiveBus-1.0.0.apk` is version 1.0.0 (code 1), targets Android API 36, supports Android API 24 and newer, and includes armeabi-v7a, arm64-v8a and x86_64. It is a release build signed with the project's existing debug signing configuration for direct installation/testing. Play Store distribution needs a separate release-signing setup.

`node tools/firebase-tests/browser.test.mjs` serves `build/web` locally, uses installed Chrome, blocks real Firebase connections, tests navigation and offline reopening, and saves screenshots. It requires the release web build first.

## Build memory correction

The supplied Java crash log showed native memory exhaustion on a machine with about 8 GB RAM while Gradle allowed an 8 GB heap and 4 GB metaspace. The project now limits Gradle to a 2 GB heap, 1 GB metaspace and two workers, with a 512 MB Kotlin daemon. This reduces build memory pressure; it does not guarantee that other programs cannot exhaust system memory.

## Useful next options

1. **Accurate ETA:** confirm stop coordinates, store the actual road path and collect real trip durations. Estimate along that path and show confidence. Straight-line distance divided by speed is inadequate on looping return routes.
2. **Transport notices:** cancellation, replacement bus and emergency timetable notices with expiry dates. A holiday calendar override selects a timetable; it should not pretend to explain a cancellation.
3. **Stop arrival alerts:** ask permission for phone notifications, then use a server-side event and push delivery. Timetable reminders and measured GPS arrivals should have different labels.
4. **Verified tracking phone:** register each official device and alert the operator when its trip has no recent fix. Device registration is an additional signal, not proof of physical bus identity.
5. **Accessibility:** full Bengali/English language selection, clearer bus announcements, high-contrast mode and a compact low-data view.
6. **Operations reports:** completed trips, missing tracking periods and punctuality summaries. Historical GPS retention should have a defined limit; this update stores trip start/end records rather than full GPS trails.
7. **Pilot feedback:** add a simple report for wrong schedule, missing stop or bus unavailable. A passenger report should never overwrite the official bus position.

## Implementation references

- [Flutter Shared Preferences](https://pub.dev/packages/shared_preferences) for local storage.
- [Firebase offline capabilities](https://firebase.google.com/docs/database/flutter/offline-capabilities) for connection and disconnect semantics.
- [Firebase rules unit testing](https://firebase.google.com/docs/rules/unit-tests) for isolated permission checks.
- [Noto Sans Bengali](https://github.com/google/fonts/tree/main/ofl/notosansbengali) is bundled with its OFL license in `assets/fonts/OFL.txt`.
- [Geolocator](https://pub.dev/packages/geolocator) for one-shot location permission and fixes. Web location requires HTTPS or a browser-trusted local development origin.



## Driver and student stop progress — 2026-11-03

Both the driver navigation panel and student arrival card use the same `StopJourney` widget. It shows the current ordered stop pair, GPS sketch progress within that pair, the next stop with a heuristic arrival range, and a connected stop timeline. Percentages refer only to the current pair, not the whole journey. Behind markers indicate projected position, not recorded arrivals. Repeated return stops retain separate indices; ambiguous direction, stale GPS and incomplete coordinates do not manufacture progress or arrival times. Offline mode retains ordered stops and explicitly labelled departure-based planning.

Driver Map and Trip history open separate pages through buttons. Neither is embedded in the main driver page. The map follows updated driver GPS while open and greys out stale fixes. History remains read-only and uses the existing authenticated database permissions. Route names fit a single line in the driver dropdown to avoid narrow-screen overflow. Bangladesh clock, trip elapsed time, private GPS preview and textual stops remain on the main page.

Local visual QA uses `flutter build web --release --target tools/driver_preview.dart --output build/driver-preview` and `node tools/firebase-tests/driver-browser.test.mjs`. This entrypoint uses explicitly labelled demo GPS, never Firebase authentication or writes, and is not the production entrypoint. Production web builds must target `lib/main.dart`. Physical driver phones, background GPS and actual bus arrival accuracy still require field testing.

Version 1.0.2 (Android code 3) includes this update. The APK build helper refreshes generated Flutter Android metadata automatically and verifies the output version. Testing APKs retain the existing debug signing configuration; keep the older APK for rollback. Web offline cache version is v6; close older tabs and reopen after deployment.


On this machine the universal 1.0.2 build exhausted memory while compiling three Android architectures at once. `powershell -NoProfile -File tools/build-apk.ps1 -TargetPlatform android-arm64` builds one architecture and labels the output `PUST-LiveBus-1.0.2-arm64.apk`. This file is for ARM64 Android devices, not older 32-bit phones or x86 emulators. The helper also accepts `android-arm`, `android-x64` or `all` for separately requested builds. A failed universal build is not a delivered artifact.


## UI text cleanup — 2026-11-05

Version 1.0.3 (Android code 4) removes long Bengali explanatory notes from driver navigation, stop progress, student arrival planning, admin sign-in and the driver roster. Functional labels, bus/stop names, displayed measurements, concise GPS/planning status and actionable instructions remain. ETA calculation, GPS freshness handling, access checks and location-storage behavior are unchanged. The web offline cache is v7.
