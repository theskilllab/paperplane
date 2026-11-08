# Paperplane

A free, open-source mobile app (iOS, iPadOS, Android) for a self-hosted
[Paperclip](https://github.com/paperclipai/paperclip). Built with Flutter.

**Status:** scaffold. There are no product features yet.

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

## Layout

| Path | Purpose |
|---|---|
| `lib/api/` | Paperclip HTTP client and models |
| `lib/auth/` | Sign-in and board-key storage |
| `lib/features/` | One folder per feature |
| `lib/ui/` | Our own components (`AppTabBar`, `AppSheet`, `AppButton`). Features import these, never a UI package directly |
| `docs/adr/` | Architecture decision records |

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
Contributors and agents also read [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE)
