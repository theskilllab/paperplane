# ADR 0004: Approval detail, conflict mapping and the Markdown renderer

Status: Accepted
Date: 2026-11-16
Authors: Engineer

## Context

PR 2a adds S4 and the shared pieces S5 and S6 reuse. The server sends a
free-form `payload` per approval type, an `inlineResolvable` gate only on the
`/attention` row, and different "already handled" statuses per endpoint. The
approval detail screen must decide inline only when the server allows it and
must never expose HTML from a request body.

## Decision

1. **Conflict mapping is per call.** `ApiClient.post` takes
   `alreadyHandledStatuses` instead of a boolean. Approvals send
   `{409, 422}`; interactions send `{409}` only, because an interaction 422 is
   a validation error that must stay visible. A cancelled request is
   `Cancelled`, not `Unexpected` (ADR 0001 §2).
2. **`inlineResolvable` comes from the row.** S4 receives the `AttentionItem`
   as the route's `extra`, so it uses the server's gate without a second
   lookup. A direct link with no row is read-only. The approval payload does
   not carry the flag.
3. **The payload renderer is generic, not per type.** Scalar values become an
   `AppKeyValueCard`; long or `plan`/`description`/`reason`-like strings are
   safe Markdown; nested maps (adapter and runtime configuration) are not
   rendered. A type the app does not know shows title, the raw summary and
   "Open in Paperclip", but keeps Approve/Reject when the row allows inline
   resolution (PRD S4 AC8).
4. **Markdown is `markdown` 7.3.1 with a local renderer.** `flutter_markdown`
   is discontinued upstream. `AppMarkdown` handles paragraphs, headings,
   lists, quotes, code, emphasis and http(s) links; raw HTML stays text, images
   become a placeholder, and a parse failure falls back to plain text. Links
   call back to the screen, which uses `url_launcher`; the renderer never
   fetches anything.
5. **The decision is one `SubmitController` per approval.** Approve and Reject
   share one in-flight state, so a second tap is ignored (PRD G6). On success
   the row is removed from the Inbox and the screen pops. On
   `AlreadyHandled`, the detail is re-read and the Inbox refreshed. A write
   403 keeps the buttons and shows the server message (PRD G4).
6. **"Who decided" has only a user id.** S4 compares it with
   `GET /cli-auth/me`: "you" on a match, otherwise "another board user"
   (THE-215 §7).
7. **The linked issue keeps the browser stopgap.** S6 does not exist yet, so
   the row opens `/{prefix}/issues/{identifier}` in the system browser. PR 3a
   replaces it with the S6 route. Like every link-out it goes through
   `url_launcher`; the app still calls only the signed-in host.
8. **Fixtures are recorded and scrubbed.** `approval_pending.json`,
   `approval_decided.json` and `approval_issues.json` follow a local
   `v2026.1106.0` instance. No pending approval existed there, so the pending
   status fields use the server's values on a recorded `hire_agent` payload;
   the fixture README says so.

## Consequences

S5 can reuse the conflict set (interactions `{409}`), `AppActionBar`,
`AppKeyValueCard`, `AppMarkdown` and the `itemTarget` row-tap function. S6 can
reuse the Markdown renderer for descriptions and comments, then replace the
linked-issue browser call with its route. Approval payloads remain a server
contract; a new type falls back to summary plus the Paperclip link instead of
crashing or leaking raw configuration.

## Reopen if

The server adds a typed approval payload schema, a stable `inlineResolvable`
field on the detail response, or a public approval page URL that does not need
the company prefix.
