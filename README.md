# RoadPulse Downloader

[![Quality](https://github.com/marktyers/roadpulse-downloader-flutter/actions/workflows/quality.yml/badge.svg)](https://github.com/marktyers/roadpulse-downloader-flutter/actions/workflows/quality.yml)
[![Coverage](https://codecov.io/gh/marktyers/roadpulse-downloader-flutter/graph/badge.svg)](https://codecov.io/gh/marktyers/roadpulse-downloader-flutter)
[![Latest release](https://img.shields.io/github/v/release/marktyers/roadpulse-downloader-flutter)](https://github.com/marktyers/roadpulse-downloader-flutter/releases/latest)

RoadPulse Downloader transfers `.rpb` recordings from a RoadPulse Logger. It
automatically finds a connected logger, downloads and validates its recording,
then helps you email or save the file.

## Download

| Platform | Download |
| --- | --- |
| macOS 13 or newer | [Download RoadPulse Downloader for macOS](https://github.com/marktyers/roadpulse-downloader-flutter/releases/latest/download/RoadPulse-Downloader-macOS.zip) |
| Windows 10 or 11 | [Download RoadPulse Downloader for Windows](https://github.com/marktyers/roadpulse-downloader-flutter/releases/latest/download/RoadPulse-Downloader-Windows.zip) |
| Android | Coming soon through Google Play |

All published versions and release notes are on the
[RoadPulse Downloader releases page](https://github.com/marktyers/roadpulse-downloader-flutter/releases/latest).

## Install on macOS

1. Download **RoadPulse-Downloader-macOS.zip** using the link above.
2. Open the downloaded ZIP file.
3. Drag **RoadPulse Downloader** into your **Applications** folder.
4. Open the app from **Applications**.

The current preview release is not yet signed and notarised by Apple. The first
time you open it, macOS may say that Apple could not verify it:

1. Click **Done** on the warning.
2. Open **System Settings**, select **Privacy & Security**, then scroll down to
   **Security**.
3. Click **Open Anyway** beside **RoadPulse Downloader**.
4. Enter your Mac password and confirm **Open**.

macOS remembers this choice, so it is normally required only once per downloaded
version. Only approve an app obtained from the official download link above.

## Install on Windows

1. Download **RoadPulse-Downloader-Windows.zip** using the link above.
2. Right-click the ZIP file, select **Extract All**, then choose a permanent
   location such as your Documents folder.
3. Keep all the extracted files together and open
   **RoadPulse Downloader.exe** from that folder.
4. Optionally right-click the program and choose **Pin to Start** or create a
   shortcut.

The current preview release is not digitally signed. If Microsoft Defender
SmartScreen appears, check that the file came from this repository, select
**More info**, then **Run anyway**. No administrator access or firewall change
is required.

## Download a recording

1. Open RoadPulse Downloader before connecting RoadPulse Logger.
2. Plug the RoadPulse Logger into the computer by USB.
3. Wait while the app discovers the logger and downloads the recording
   automatically. The screen reads **Downloading retained records…** during the
   transfer.
4. Wait for the beep. The beep means the `.rpb` file has been completely
   downloaded and passed its integrity checks; the logger can now be unplugged.
   The app shows the earliest and latest recording dates, including the year,
   so you can confirm that RoadPulse Logger has been recording recently.
5. Confirm the prompt to create the email. Your email program opens with the
   `.rpb` file attached, the RoadPulse Logger serial number as the subject, and the
   RoadPulse delivery address filled in. Review it and press **Send**.

On macOS and Windows, **Email** is selected by default. Select **Save locally**
before connecting the logger if you want to choose a folder instead. The app
only reads from the logger and does not modify its storage.

## Troubleshooting

- **The logger is not detected:** unplug it, close the app, reopen the app and
  reconnect it. Try another data-capable USB cable or USB port if necessary.
- **The logger is not detected when other USB devices are attached:** disconnect
  unrelated USB serial devices, then unplug and reconnect the logger.
- **No email window appears:** make sure a default email application is
  configured. The validated file remains available in the app, where it can be
  saved locally and attached manually.
- **The beep sounds but no message was sent:** the beep confirms the download,
  not email delivery. The final email is sent only after you approve it in your
  email application.
- **macOS blocks the app:** follow the **Open Anyway** instructions in the macOS
  installation section above.
- **Windows blocks the app:** use **More info → Run anyway** only after confirming
  that it was downloaded from the official link above.

## For developers

The shared Dart implementation is divided into protocol validation, transport,
download control, and adaptive UI layers. Desktop loggers use USB serial;
Android uses USB host mode and requires an OTG adapter. iOS is not currently a
supported target because an ordinary iPhone or iPad app cannot access the
logger's USB CDC serial interface.

Every push and pull request checks formatting, performs static analysis, and
runs the complete unit, regression, controller, and UI test suites with coverage.
Version tags build the macOS and Windows downloads. Android deployment uses a
protected manual Google Play workflow.

See [the protocol documentation](docs/protocol.md) for the behaviour preserved
from the original macOS utility and [the release guide](docs/releases.md) for
build, signing, platform permission, and Google Play requirements.

```sh
flutter pub get
flutter analyze
flutter test --coverage
```

macOS builds require macOS with Xcode, CocoaPods, automake, and libtool. Windows
builds require Windows with Visual Studio's **Desktop development with C++**
workload. The logger must appear as a serial/COM device.
