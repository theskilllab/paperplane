# ADR 0001: Shared foundations and conventions

Status: Proposed
Date: 2026-11-08
Authors: Tech Lead

## Context

PR 1.0 lays the code that PR 1a, 1b, 2 and 3 build on, so they can run in
parallel (feasibility §4, F1–F8). The stack is decided in the `adr-stack`
ADR (Flutter, Riverpod, go_router, dio, `flutter_secure_storage`). This ADR
records the choices inside that stack that feature PRs must follow, and where
this PR differs from the written spec.

## Decision

1. **Layers.** `lib/api/` (client, error, models, no UI imports) →
   `lib/data/` (one repository per feature, Http and Fake) → `lib/app/`
   providers → `lib/features/` screens → `lib/ui/` components. Screens read
   repositories only through providers, so demo mode and tests swap in the
   Fakes.
2. **One error type.** Every failure is a sealed `ApiError`. Screens never
   see `DioException`. `presentationFor` is the only place that writes error
   copy. 409 and 422 become `AlreadyHandled` **only** for calls made with
   `stateConflict: true` (decision calls); for other writes they are
   `Server(status)`, so a validation failure is never shown as "already
   handled". The one text match in the client is the 403 hostname message,
   because the server gives no other signal for it.
3. **Never log secrets.** The client logs only method, path and status. It
   never logs the host, the query, a body, `Authorization` or anything
   matching `pcp_board_`. A test enforces it.
4. **A 401 signs out.** `ApiClient.onUnauthorized` fires only when the request
   carried a key, so a wrong password at sign-in does not look like an expired
   session.
5. **Models are hand-written** with tolerant parsing (missing or odd fields
   never throw; an unknown `sourceKind` is `SourceKind.unknown`). `inlineResolvable`
   defaults to false: the server decides what may be resolved inline.
6. **Riverpod without code generation.** Plain `Notifier` and `Provider`.
   Automatic provider retry is off (`ProviderScope(retry: …)`) because the
   user taps Retry and writes must not repeat.
7. **Components are `App…`** (`AppButton`, `AppSheet`, `AppTextField`, …) to
   match the scaffold, not the design spec's `Pp…`. Tokens are
   `PaperplaneTokens` (`context.pp`).
8. **Fixtures are synthesized**, not recorded, until PR 1b records and scrubs
   real payloads. `fixtures_hygiene_test.dart` fails on a key, a real-looking
   hostname, an email domain or an IP address.

## Deviations from the written spec

- No `freezed`, `json_serializable`, `riverpod_generator` or `build_runner`
  (F1 mentions `build_runner`). Hand-written models are short and tolerant
  parsing needs hand code anyway. Add codegen when a PR shows it pays off.
- `ApiError.Timeout` is named `TimedOut`: `Timeout` clashes with
  `package:test` in every test file.
- `dangerInk` (`#B8312A`) is a new token. The design spec says all text pairs
  pass 4.5:1, but `danger` on `dangerSoft` is 4.41:1. `dangerInk` (4.86:1) is
  used for error banner and "bad" pill text. `ok` (4.34:1) and `todo` (3.98:1)
  also miss 4.5:1 but only color status icons, which need 3:1.
- Icons are 16 original SVG drawings in the prototype's style, kept as Dart
  strings in `lib/ui/theme/app_icons.dart` (the prototype's path data is not
  in the repo). Review: Product Designer.
- Review status icon uses the right-half-filled shape and the cancelled icon
  is a circle with a cross (design spec Q1 proposals, not yet confirmed).
- A phone bottom sheet cannot block a drag-to-dismiss while a request is in
  flight (Flutter fixes that option when the route opens). Back and scrim taps
  are blocked via `locked`. The request still completes.

## Consequences

Feature PRs touch their own repository file, their own provider line and
their own route, so they rarely conflict. Hand-written parsing costs a little
typing per model. The Fake repositories double as demo mode, so they must keep
covering all 11 `sourceKind`s (a test checks it).

## Reopen if

Models grow past what hand parsing can keep correct, or the server publishes
real response types.
