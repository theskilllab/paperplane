# ADR 0003: Real sign-in, key handling and offline cache

Status: Accepted
Date: 2026-11-12
Authors: Engineer

## Context

PR 1b connects S1 to a real Paperclip instance and makes S2 read live data. It
follows the THE-203 spike (password-first, device login as fallback), the PRD
S1 acceptance criteria and the CEO conditions from the PR 1.0 review.

## Decision

1. **Password-first sign-in.** `POST /auth/sign-in/email`, then
   `POST /board-api-keys` with the session cookie, then
   `POST /auth/sign-out` to end the browser session. The cookie lives in
   memory for those calls only; it is never stored. `Origin` is the server
   origin on sign-in, mint and sign-out, because the server's board mutation
   guard needs it (THE-203 A1).
2. **The key is explicit.** The app asks for `expiresAt = now + 30 days`
   (never `null`, which would mean "never expires") and
   `name = "Paperplane (<device>)"`. The new key is verified with
   `GET /cli-auth/me` before it is stored. An account with no company is
   rejected and the key is revoked.
3. **Device login is the fallback.** `POST /cli-auth/challenges` returns the
   inert `boardApiToken`; the approved poll does not repeat it. The poll path
   is prefixed with `/api` and sends the challenge token. `Retry-After` is
   obeyed, and cancel is best effort. The approval page must resolve to the
   session origin; an absolute URL for another host is ignored.
4. **A late 401 does not sign out a newer key.** `ApiClient` reports the key
   the failed request actually carried. `SessionController.handleUnauthorized`
   ignores it when it does not match the current session. This covers a
   request that was in flight during sign-out and sign-in.
5. **A 401 still signs out.** Matching-key 401s delete the key and cached
   answers and return to S1 with the address prefilled (PRD G3).
6. **Cache only server answers.** The last `GET /companies` and `/attention`
   bodies are kept as raw JSON in preferences, with the feed's company id and
   fetch time. A cold start shows the cached feed immediately and refreshes
   behind it, so one poll failure adds the offline banner instead of a blank
   screen (PRD S1 AC11). Sign-out, 401 and a company switch clear the cache.
7. **The iOS Keychain orphan is removed.** Keychain items survive an app
   reinstall while preferences do not. If there is no stored address at
   startup, every `board_key:` item is deleted (no usable key can reach it).
8. **Transport stays conservative.** The client still never follows a
   redirect, so the key cannot be resent to a different host. Plain `http`
   remains restricted to private hosts by the host-string rule.
9. **Recorded fixtures.** `test/fixtures/attention_feed.json` is a recorded,
   scrubbed `/attention` answer, parsed by a contract test. Demo data remains
   invented and covers every `sourceKind` on its own.

## Consequences

S1 owns the sign-in form, paste-token sheet and browser sheet under
`lib/features/connect/`; the HTTP calls live in `lib/data/auth_repository.dart`.
The auth repository is separate from the signed-in session repository because
it runs before a session exists. Cached answers are not encrypted; they are
content the app already shows and never contain the board key. Key rotation
(PR 3) can reuse `/cli-auth/me.keyId` and `DELETE /board-api-keys/{id}`.

## Reopen if

The server adds a token endpoint that does not need a browser cookie, changes
the key expiry contract, provides a stable approval URL for device login, or
the cache needs encryption at rest.
