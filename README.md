# SHMed

SHMed is a Flutter pharmacy management app. The repository includes authentication, pharmacy inventory and reporting flows, Hive-backed local data, Firebase integration, notifications, and an optional medicine recommendation workflow. See the source and dependency manifest for the current implementation.

## Requirements

- Flutter and Dart versions compatible with `pubspec.yaml`
- Firebase project configuration for Firebase features
- A local `.env` file for optional desktop configuration; use `.env.sample` as a template and never commit real credentials

## Run locally

```bash
flutter pub get
flutter run
```

Configure platform-specific Firebase files before launching features that require Firebase. Keep API credentials out of source control.


## AI integration and credentials

The optional medicine recommendation feature should be limited to medicines already stored in the app’s Hive database. Validate any generated recommendation before presenting it to a user.

For desktop builds, the app can load local configuration from `.env`; use `.env.sample` as the template. Keep real API keys and other credentials out of source control, and never commit a populated `.env` file.
