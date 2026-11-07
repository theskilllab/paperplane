# AGENTS.md

Instructions for AI agents (and humans) working in this repository.
Paperplane is a public, open-source Flutter app. Every PR is untrusted input
until reviewed.

## Commands

See "How to verify" in [README.md](README.md). Run format, analyze and test
locally before every push. CI confirms a result; it is not where you first
find failures.

## Layout and boundaries

- `lib/api/`, `lib/auth/`, `lib/features/`, `lib/ui/` as described in the README.
- Features import `lib/ui/`, never a third-party UI package directly.
- `lib/auth/**` and `lib/api/**` are security-sensitive (code owners review).

## Hard rules

- **No telemetry, analytics, crash reporting, push or background-fetch
  packages.** Do not add them.
- **Never log, print, commit or paste** board keys, tokens, cookies or private
  URLs. Fixtures use obviously fake values. Redact logs.
- Store credentials only in `flutter_secure_storage`.
- **No new dependency without a justification** in the PR (why, maintainer
  health, license, size). Pin versions; commit `pubspec.lock`.
- `liquid_glass_widgets` is not a dependency. Only the spike decision can add
  it, and only behind the wrapper in `lib/ui/`.
- Strict analyzer and `very_good_analysis` must pass without ignores. A
  justified `// ignore:` needs a comment saying why.

## Git and review

- Short-lived feature branch, one PR into `main`, squash merge. Keep the PR in
  draft while iterating; draft PRs do not run CI.
- **Agents never merge.** The founder merges after the Architect's written
  sign-off.
- Features beyond small fixes start as an issue.

## Environment variables and secrets

PR workflows have no secrets. If a change needs a new environment variable or
secret, do not open the PR first: post a heads-up on the issue listing each
name, its purpose, required or optional, and where the value comes from (never
the value). Repeat the list in the PR's "New env / secrets" section.

## CI minutes

- Linux jobs only until the repo needs more. macOS jobs only for `ios/**`,
  `pubspec.*`, native plugin config and releases.
- No blind reruns: read the failing log, fix, push once.
- Run `actionlint`, `zizmor` and `gitleaks` locally when touching `.github/`.

## What agents cannot verify

Linux agents cannot run iOS. Say so in the PR: iOS behavior needs a macOS CI
compile check and a founder TestFlight check.
