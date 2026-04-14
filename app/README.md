# app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Environment variables (Supabase)

This app reads Supabase config from Dart defines:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `GOOGLE_WEB_CLIENT_ID`

### Recommended local setup

1. Copy `env/dev.example.json` to `env/dev.json`.
2. Fill real values in `env/dev.json`.
3. Run the app with:

```bash
flutter run --dart-define-from-file=env/dev.json
```

### Android Studio / IntelliJ

Edit your Flutter Run Configuration and add this to **Additional run args**:

```text
--dart-define-from-file=env/dev.json
```

### VS Code

Use the launch config `Flutter (Supabase Env)` from `.vscode/launch.json`.

## Google In-App Sign-In Setup (Android)

Complete this sequence before testing Google auth:

1. Enable Google provider in Supabase Auth and set redirect URL `rasoi://login-callback`.
2. In Firebase/Google Cloud, register Android app package `com.example.app` with your debug SHA-1.
3. Download `google-services.json` and place it at `android/app/google-services.json`.
4. Set `GOOGLE_WEB_CLIENT_ID` in `env/dev.json`.
5. Run with `--dart-define-from-file=env/dev.json`.

Expected behavior after setup: tapping Google sign-in on login/signup opens native account chooser in-app (no external browser tab).
