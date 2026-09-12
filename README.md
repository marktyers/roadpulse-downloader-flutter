# RoadPulse Downloader (Flutter)

Cross-platform replacement for the native RoadPulse Downloader. Its supported
release targets are macOS, Windows, and Android. USB capture remains read-only:
the application
never sends a command to the logger and never modifies its flash.

## User workflow

1. Start the app before plugging in the RoadPulse Logger.
2. Connect the logger by USB. A single likely logger is selected and connected
   automatically; when several serial devices exist, choose one from the list.
3. Wait for the length-framed download and RPB validation to finish.
4. On macOS or Windows choose **Email** (the default) or **Save locally**, then
   click the delivery button. On Android tap **Create email**. On macOS and
   Android a pre-addressed draft opens with the validated `.rpb` attached and
   the logger ID as its subject; the destination is deliberately hidden from
   the application UI. Windows opens its system attachment share flow.

The proposed filename is `RP-XXXXXX-yyyy-MM-dd-HHmmss.rpb`. Email apps retain
the final send/consent step. Fully unattended sending would require a separately
authenticated RoadPulse mail service; credentials are never embedded in this
application.

The supplied `assets/beep.wav` plays once the download has completed and the RPB
has passed every integrity check. The app then asks whether to send the email;
confirming opens the pre-addressed draft with the RPB attached. The sound means
the logger can be unplugged—it does not claim that an email has already been sent.

## Initial platform generation

Flutter was not installed on the development Mac when this project was created.
An attempted SDK install could not unpack because the disk had only 186 MB free.
After installing Flutter 3.29 or newer, run this once from the project root:

```sh
flutter create --platforms=macos,windows,android,ios --org uk.co.roadpulse .
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

### Deferred iOS target

- The iOS runner is retained for possible future work, but iOS is not currently
  a supported release target. The logger's current USB
  CDC serial interface is not accessible to an ordinary iPhone/iPad app.
- A functional iOS downloader requires a logger firmware/hardware transport
  supported by iOS: BLE, a network protocol, or Apple's External Accessory/MFi
  programme. The app shows this limitation instead of attempting desktop serial
  access at runtime.
- Building requires full Xcode. Device installation and distribution require an
  Apple Development/Distribution team and the usual signing profiles.

## Design

- `lib/src/protocol`: pure Dart framing and RPB validation, shared everywhere.
- `lib/src/transport`: desktop serial and Android USB implementations.
- `lib/src/download_controller.dart`: discovery, timeout, progress, and state.
- `lib/src/ui`: adaptive Material desktop/mobile workflow and delivery.
- `test`: framing and validation regression tests ported from the Swift app.

See [docs/protocol.md](docs/protocol.md) for the exact reverse-engineered
behaviour of the original macOS utility.

## Automated releases

GitHub Actions checks every push and pull request. Version tags build downloadable
macOS and Windows ZIP files and publish a GitHub Release. A separately protected,
manual workflow builds a signed Android App Bundle and deploys it to a selected
Google Play track. See [docs/releases.md](docs/releases.md) for setup, required
secrets, signing limitations, and the recommended internal-track rollout.
