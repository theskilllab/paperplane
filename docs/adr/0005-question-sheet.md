# ADR 0005: Question and confirmation sheet (S5)

Status: Proposed
Date: 2026-11-19
Authors: Engineer

## Context

PR 2b adds S5. `issue_thread_interactions` is one table with six kinds and a
free-form `payload`. Some confirmations carry a governed action
(`toolAction`, `secretProposal`, connection authorization) or a document
target that can go stale. Approving one of those from a phone without its
risk, preview and expiry is unsafe (THE-215 risk 1). The API has no
get-by-id route, and an interaction 409 means already resolved while a 422 is
input validation.

## Decision

1. **Only four kinds resolve inline.** A plain `request_confirmation`
   (no `toolAction`, no `secretProposal`, no connection authorization, no
   `stale_target`), an `ask_user_questions` form of choices and simple free
   text, `suggest_tasks` and `request_checkbox_confirmation`. Every other
   kind (`request_item_verdicts`, `connection_intent`, unknown) and every
   guarded confirmation shows the heading and summary with "Open in
   Paperclip" and no inline action (PRD S5 AC1, amended).
2. **Question support is conservative.** Choices, single and multi select,
   and simple free text resolve inline. A question with an `initialText`, a
   regex, numeric bounds or an `integer`/`number` input type opens in
   Paperclip instead, because this version cannot enforce that validation.
   The storage `questions` list supplies option ids; the canonical
   `questionSet` supplies the answer mode and text rules.
3. **There is one sheet, fed by the list.** `InteractionRepository` exposes
   `list`, `respond`, `accept`, `reject` and `find`; `find` re-reads the
   issue's list because the server has no get-by-id call. Every write is
   followed by the server's own row; a short receipt triggers another list
   read.
4. **409 and 422 mean different things.** `ApiClient.post` gets
   `alreadyHandledStatuses: {409}`. A 409 is `AlreadyHandled` and re-reads;
   a 422 or 400 stays `Server(status, message)` and shows the server's text,
   so "Select at least one suggested task" is not hidden as "Already
   handled" (ADR 0001 §2).
5. **The route hosts a modal sheet.** S5 is a route so a row tap, a deep
   link and the browser stopgap share one place. The route page is
   non-opaque and the form is the standard `showAppSheet` modal, so the Inbox
   stays painted while the sheet slides in. Closing the sheet pops the
   route; typed text asks for confirmation before a close that is not a
   submit.
6. **The sheet keeps the user's input.** Answers live in the sheet's state,
   not in the request. A failed submit keeps selections and text; a 403 is
   read-only with the server message; a 409 shows "Already handled" while
   the re-read current state replaces the form. One shared
   `SubmitController` per interaction ignores a second tap (PRD G6).
7. **The question row leaves the browser stopgap.** `itemTarget` reads the
   issue id from `subject.metadata.issueId` (or the href) and the interaction
   id from the `#interaction-<id>` fragment. All other question-like rows,
   including unknown kinds, still open Paperclip.
8. **Fixtures are recorded and scrubbed.** `test/fixtures/interactions.json`
   holds recorded rows from a local `v2026.1106.0` instance, with ids, text
   and timestamps replaced by fake values; field names, types and enum values
   are unchanged. No `suggest_tasks` or `toolAction` row existed on that
   instance, so those two payloads follow the server validators and are
   marked as synthesized in the fixture README. The checkbox payload is
   recorded, with the status changed to `pending` so the sheet renders it.

## Consequences

S5 can answer the four inline kinds on a phone. A tool call or secret grant
can only be approved in Paperclip, which is the safe failure mode. A server
that adds a seventh kind falls back to "Open in Paperclip" without a crash.
Supporting `toolAction` or number/text-validated question modes later means
adding a renderer and removing that case from the gate; it does not change
the repository contract.

## Reopen if

The server adds a get-by-id route, a typed interaction query with only pending
rows, a stable "stale target" flag before resolution, or a safe native way to
show tool-action risk and previews.
