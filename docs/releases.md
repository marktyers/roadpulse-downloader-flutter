# Releases and store deployment

## Continuous quality

Every push to `main` and every pull request checks formatting, runs Flutter
analysis, and executes the complete test suite.

## Desktop downloads

Pushing a tag such as `v0.1.0` builds macOS and Windows ZIP files and attaches
them to a public GitHub Release. The workflow can also be run manually to obtain
temporary Actions artifacts without creating a release.

The initial macOS ZIP is not Developer ID signed or notarised, and the Windows
ZIP is not Authenticode signed. Users may therefore see Gatekeeper or SmartScreen
warnings. Production distribution should add signing identities as protected
GitHub environment secrets before advertising the downloads broadly.

## Google Play

The Android application ID is permanently set to
`uk.co.roadpulse.downloader`. Create that application in Play Console before the
first workflow run and enable Play App Signing.

Create a protected GitHub environment named `google-play` and add:

- `ANDROID_KEYSTORE_BASE64`: base64 representation of the upload `.jks` file.
- `ANDROID_KEYSTORE_PASSWORD`: upload-keystore password.
- `ANDROID_KEY_PASSWORD`: upload-key password.
- `ANDROID_KEY_ALIAS`: upload-key alias.
- `PLAY_SERVICE_ACCOUNT_JSON`: complete Google Play service-account JSON.
- `DELIVERY_EMAIL`: fixed recipient compiled into release applications. Store it
  as a repository secret as well so desktop release jobs can use it.

Grant the service account release permissions for the Play Console application.
Run **Publish Android to Play Store** manually and begin with the `internal`
track. Each upload requires a version code greater than every prior upload, so
increment the `+1` portion of `version` in `pubspec.yaml` before publishing the
next build. Protect production deployments with required reviewers in the
`google-play` GitHub environment.
