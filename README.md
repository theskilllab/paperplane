# Paperplane

A free, open-source mobile app (iOS, iPadOS, Android) for a self-hosted
[Paperclip](https://github.com/paperclipai/paperclip). Built with Flutter.

**Status:** shared foundations (API client, error model, repositories, UI
kit, app shell). Screens S1–S7 are stubs; later PRs build them.

Principles: no telemetry, no push notifications, no background fetch. The app
talks only to the Paperclip server you sign in to.

## Requirements

- [FVM](https://fvm.app) (or any Flutter install matching `.fvmrc`).
  The pinned Flutter version is in [`.fvmrc`](.fvmrc).
- For the Android build: JDK 17 and the Android SDK.
- iOS builds need macOS and Xcode. CI does not build iOS yet.

## Setup

```sh
fvm install            # installs the version in .fvmrc
fvm flutter pub get
```

Without FVM, use `flutter` in place of `fvm flutter` below.

## How to verify

Run these before every push. CI runs the same steps.

```sh
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze
fvm flutter test
fvm flutter build apk --debug      # needs the Android SDK
```

Workflow and secret checks (needed when you change `.github/`):

```sh
actionlint
zizmor .github
gitleaks git --redact
```

The golden test lives in `test/ui_golden_test.dart`. After an intended UI
change, regenerate the image and review it in the diff:

```sh
fvm flutter test --update-goldens
```

The golden renders Flutter's test font (Ahem blocks), so it checks surface,
shape and layout, not glyphs or icons. That keeps it stable across CPU
architectures.

## Run the demo (no server needed)

Demo mode runs on invented data and never touches the network:

```sh
fvm flutter run --dart-define=PAPERPLANE_DEMO=true
```

## Layout

| Path | Purpose |
|---|---|
| `lib/app/` | App shell: `AppEnv` (demo flag), providers, go_router with every S1–S7 route (stubs until built) |
| `lib/api/` | `ApiClient` (dio), sealed `ApiError`, redacting logger, base-URL rules, hand-written models with tolerant parsing |
| `lib/data/` | One repository per feature (abstract + Http + Fake); `lib/data/fake/` holds the demo data |
| `lib/auth/` | `KeyStore` (board key in platform secure storage), `SessionController`, small preferences |
| `lib/core/` | `SubmitController` (one write at a time), `presentationFor` (error → user copy) |
| `lib/features/` | One folder per feature (screens) |
| `lib/ui/` | Our own components and design tokens (`lib/ui/theme/`). Features import `package:paperplane/ui/ui.dart`, never a UI package directly |
| `test/fixtures/` | Fake server answers (synthesized; see its README) |
| `docs/adr/` | Architecture decision records |

Conventions for feature PRs are in [ADR 0001](docs/adr/0001-shared-foundations.md).

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
Contributors and agents also read [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE)
