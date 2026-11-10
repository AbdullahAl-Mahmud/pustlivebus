# App and web downloads

[Download release files](https://github.com/AbdullahAl-Mahmud/pustlivebus/releases/tag/v1.0.3).

| File | Version | Purpose |
| --- | --- | --- |
| `PUST-LiveBus-1.0.3-arm64.apk` | 1.0.3 (4) | Current Android testing app; ARM64, Android 7.0+ |
| `PUST-LiveBus-Web-1.0.3.zip` | 1.0.3 (4) | Current compiled website; extract and serve over HTTP/HTTPS |
| GitHub Source code ZIP / tar.gz | 1.0.3 | Flutter source at this release tag |
| `PUST-LiveBus-1.0.2-arm64.apk` | 1.0.2 (3) | Older ARM64 testing APK |
| `PUST-LiveBus-1.0.0.apk` | 1.0.0 (1) | Older universal testing APK |
| `SHA256SUMS.txt` | — | Checksums of the uploaded APKs and web ZIP |

Older APKs are archived binary builds. Their historical source snapshots and compiled web builds were not retained, so this release's source archive represents 1.0.3 only. No 1.0.1 APK was retained.

APKs use the existing debug signing configuration for installation and testing. They are not Play Store release-signing packages. Updating an existing installation requires a compatible signing certificate. The current APK is for ARM64 Android devices; older 32-bit phones and x86 emulators need a separately built current APK.

The web ZIP contains the built frontend and public Firebase client configuration. It does not contain database records, passwords, owner credentials or private keys. Source installations require `flutter pub get`; the web download can be hosted as static files. Use HTTPS for phone geolocation. [Open the hosted app](https://pustlivebus.web.app).

iOS, Windows, macOS and Linux source folders are in the repository. Installable IPA, EXE and desktop packages have not been built or uploaded.
