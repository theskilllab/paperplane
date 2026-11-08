# Contributing to Paperplane

Thanks for helping. Paperplane is MIT licensed. There is no CLA and no DCO.

## Before you start

- Small fixes: open a PR directly.
- Anything bigger (a feature, a new dependency, a change to `lib/auth/` or
  `lib/api/`): **open an issue first** and agree on the approach.
- Read [AGENTS.md](AGENTS.md) for the hard rules (no telemetry or push, no
  secrets in logs, wrapper-only UI packages).

## Set up and verify

See "How to verify" in [README.md](README.md). Run format, analyze and test
before every push.

## Pull requests

- Branch from `main`; keep the PR small and focused. Use a draft PR while you
  iterate: draft PRs do not run CI.
- Fill in the PR template: what and why, linked issue, test evidence,
  **New env / secrets** (names only, or "none"), new dependencies with a
  justification, security impact, and an accessibility check for UI changes.
- Add or update tests. UI changes need a widget or golden test.
- Changes under `.github/`, `android/`, `ios/`, `pubspec.*`, `lib/auth/`,
  `lib/api/`, `SECURITY.md` and `LICENSE` need review from the code owners
  (see `.github/CODEOWNERS`).
- PRs are squash merged by a maintainer. Contributors and agents do not merge.
- PRs from forks run CI only after a maintainer approves the run.

## Dependencies

Every new dependency needs a justification: why it is needed, maintainer
health, license, and size impact. `pubspec.lock` is committed. Telemetry,
analytics, crash-reporting and push packages are not accepted.

## Never share secrets

Do not paste tokens, board keys, cookies or private URLs into issues, PRs,
logs or screenshots. Redact them first. Report vulnerabilities privately; see
[SECURITY.md](SECURITY.md).

## Decisions

Architecture decisions are recorded in `docs/adr/` using the template there.
