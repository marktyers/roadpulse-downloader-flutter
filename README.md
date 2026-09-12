# RoadPulse Downloader (Flutter)

Cross-platform replacement for the native RoadPulse Downloader. It targets
macOS, Windows, and Android and keeps USB capture read-only: the application
never sends a command to the logger and never modifies its flash.

## User workflow

1. Start the app before plugging in the RoadPulse Logger.
2. Connect the logger by USB. A single likely logger is selected and connected
   automatically; when several serial devices exist, choose one from the list.
3. Wait for the length-framed download and RPB validation to finish.
4. On macOS or Windows choose **Email** (the default) or **Save locally**, then
   click the delivery button. On Android tap **Create email**. The system share
   chooser opens with the validated `.rpb` attached; choose an email app.

The proposed filename is `RP-XXXXXX-yyyy-MM-dd-HHmmss.rpb`. Email apps control
the final draft UI. A portable app cannot silently create an attachment using a
`mailto:` URL, so the operating-system share sheet is used.

## Initial platform generation

Flutter was not installed on the development Mac when this project was created.
An attempted SDK install could not unpack because the disk had only 186 MB free.
After installing Flutter 3.29 or newer, run this once from the project root:

```sh
flutter create --platforms=macos,windows,android --org uk.co.roadpulse .
flutter pub get
```

Keep the existing `lib`, `test`, `pubspec.yaml`, `README.md`, and `docs` files if
Flutter asks about conflicts. The command generates only the standard native
runner projects and plugin registrants.

## Verify and build

```sh
flutter analyze
flutter test
flutter run -d macos
flutter build macos --release
flutter build windows --release
flutter build apk --release
```

Windows builds must run on Windows. macOS builds must run on macOS.

## Platform requirements

### macOS

- Xcode with Command Line Tools, CocoaPods, and Flutter desktop support.
- Minimum deployment target: macOS 13.
- Direct serial access must be permitted. Add the following entitlement to both
  `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.device.serial</key>
<true/>
```

  A direct-distribution build may instead disable App Sandbox, matching the
  existing non-sandboxed app. Test the entitlement/signing route before a Mac
  App Store submission.
- The `flutter_libserialport` package bundles libserialport. Signing and
  notarisation must include all bundled native libraries.

### Windows

- Windows 10/11, Visual Studio 2022 with **Desktop development with C++**,
  the Windows 10/11 SDK, CMake, and Flutter desktop support.
- The logger must enumerate as a COM port. Modern USB CDC ACM devices normally
  use the inbox `usbser.sys` driver; otherwise install the logger/vendor INF.
- No network capability, firewall exception, or administrator access is needed.

### Android

- Android Studio/SDK, USB host capable phone/tablet, and an OTG cable/adapter.
- The app requests USB-device permission through Android's system dialog.
- Ensure the generated `android/app/src/main/AndroidManifest.xml` contains:

```xml
<uses-feature android:name="android.hardware.usb.host" android:required="true" />
```

- Set Android `minSdk` to at least 21 if the generated project is lower.
- No storage permission is required: the attachment is staged in app-private
  temporary storage and shared using the platform's secure content provider.

## Design

- `lib/src/protocol`: pure Dart framing and RPB validation, shared everywhere.
- `lib/src/transport`: desktop serial and Android USB implementations.
- `lib/src/download_controller.dart`: discovery, timeout, progress, and state.
- `lib/src/ui`: adaptive Material desktop/mobile workflow and delivery.
- `test`: framing and validation regression tests ported from the Swift app.

See [docs/protocol.md](docs/protocol.md) for the exact reverse-engineered
behaviour of the original macOS utility.
