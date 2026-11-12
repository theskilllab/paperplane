# ADR 0002: Inbox, company switcher and demo entry

Status: Proposed
Date: 2026-11-09
Authors: Tech Lead

## Context

PR 1a builds S2 (Inbox) and S3 (company switcher) on the Fake repositories
from [ADR 0001](0001-shared-foundations.md). The choices below are not in the
PRD or the design spec.

## Decision

1. **One controller per company.** `inboxProvider` is an auto-disposed family
   keyed by company id. Switching company drops the old feed, and an answer
   that arrives later lands on a disposed controller and is ignored (S3 AC6).
   A refresh is `invalidateSelf`, so Riverpod keeps the old rows next to a
   failure (banner "Last updated"), and a `busy` flag stops overlapping
   requests.
2. **Polling lives in the screen.** A 30 s timer runs only while the app is
   resumed and no full page covers the Inbox (`RouteObserver<PageRoute>`;
   sheets do not pause it). Returning to the foreground or from a detail page
   refreshes at once. The poll never restarts a feed that failed to load.
3. **Browser stopgap.** `url_launcher` opens `baseUrl + subject.href`. Only a
   plain absolute path is followed; a full URL or `//host` from the server is
   treated as "no link", so a bad payload cannot send the user elsewhere. In
   demo mode a toast explains instead, because the demo host does not exist.
   New dependency: `url_launcher` 6.3.3 (flutter.dev, BSD-3, no telemetry; it
   adds only its platform packages).
4. **S3 is a sheet, not a route.** `AppRoutes.companies` is removed. Hidden
   when the user has one company; Sign out is in the sheet and in an account
   row at the bottom of the Inbox ("Disconnect this server?", with revoke; if
   the revoke fails offline the key is still deleted locally and the user is
   told it may stay active).
5. **Demo entry.** S1 is still a stub; it gets an "Explore the demo" button so
   the app is usable without `--dart-define`. PR 1b replaces the screen.
6. **Screenshots** are rendered by `test/screenshots_test.dart` with the real
   Inter font and written only on request. They are not compared in CI: real
   glyphs differ slightly between CPU architectures.

## Consequences

Not built here: persisted feed cache for a cold start without network (S1 AC11,
PR 1b, needs a real session) and "Not encrypted" on S1.

## Reopen if

Polling needs to differ per screen, or the server publishes a push channel.
