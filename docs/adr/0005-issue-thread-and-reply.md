# ADR 0005: Issue thread and reply (S6)

Status: Proposed
Date: 2026-11-15
Authors: Tech Lead

## Context

PR 3a builds S6 (issue header, description, thread, reply) on the foundations
of [ADR 0001](0001-shared-foundations.md). The server's comment API and the
PRD leave several choices open. The server facts below come from recordings
(`test/fixtures/README.md`) and from the Paperclip source.

## Decision

1. **Paging.** The server lists comments newest first. `GET
   /issues/{id}/comments?order=desc&limit=51` gives the newest page (one extra
   item says "there is an earlier page"). `after=<id>` with `order=desc`
   returns the comments *older* than that id, not the id itself. The screen
   shows them oldest to newest and keeps the oldest loaded id as the cursor.
   Page size is 50.
2. **Deleted anchor.** An `after` id the server no longer has answers **200
   with an empty list**, which looks like "no more". When "Load earlier"
   gets an empty page while an earlier page was promised, the controller
   re-anchors on the next older held comment that still works and drops the
   ids the server no longer has. It reads at most one page per step, so the
   server's 500-comment `limit` cap can never be mistaken for the start of the
   thread, and earlier held pages are kept. If no held comment works as a
   cursor, the loaded comments stay and `hasEarlier` is left unknown (the
   button remains) rather than ending the thread. A deleted comment that the
   server still lists stays in the held list (it can be a cursor) and is not
   drawn.
3. **Refresh.** Open, pull-to-refresh and Retry read the issue and the newest
   page. If the page overlaps what is held, the page's version of each comment
   wins and older pages stay; if it does not (more than 50 new comments) the
   list is replaced by the newest page. **No polling** (PRD S6 AC7).
4. **Reply is optimistic and idempotent.** Send adds a pending reply at the
   bottom at once, with a `clientRequestId` (random UUID v4). The server
   returns the existing comment for the same id and body, and a 409 for the
   same id with another body. So "Not sent — Retry" resends the **identical
   body with the same id**. "Edit" normally removes the pending reply, puts the
   text back in the composer and the next send gets a **new id**. The body is
   built once, at send time, and stored.
   - **Uncertain outcome.** An `Offline`, `TimedOut`, `Tls`, `Unexpected` or 5xx
     answer can hide a stored comment. Before Edit drops that pending id, the
     controller reads the newest comments and looks for the id. It walks older
     pages too, because comments that arrive while the user waits can push the
     reply off the newest page. The walk is bounded at ten pages (500 comments
     at the 50-comment page size); if the id is still not found, the app warns
     instead of dropping the id on a guess. An older-page read whose `before`
     anchor the server no longer has answers an empty page with
     `hasEarlier: false` (decision 2), which looks like the start of the
     thread; that answer is also treated as unresolved, so a deleted anchor
     cannot drop the id. Only a genuinely empty newest page (a thread with no
     comments) is safe to edit. If the reply is there, it becomes a
     normal comment and Edit does not open the composer ("already sent"). If
     the check itself fails, the app also warns that sending again can post
     twice and lets the user cancel or edit anyway. A 4xx is a definite refusal
     and needs no read.
   - A pending reply that the server already lists (answer lost) is also
     dropped on the next refresh by its `clientRequestId`.
   - **Leaving S6.** Pending replies and composer text live only in S6's
     auto-disposed controller. Leaving the screen drops a reply that was never
     confirmed, including its id and Retry path; there is no background queue
     in M2, so nothing is sent after the user leaves. The recovery paths are
     Retry while S6 is open and pull-to-refresh, which reconciles a stored
     comment. If this proves too easy to lose in use, keep the draft in a
     non-disposed provider (follow-up).
   - Writes are never queued: offline fails at once and keeps the text (G2).
     One send at a time (G6): the send button and the Retry/Edit buttons are
     disabled while one is in flight.
5. **@agent is a button, not inline autocomplete** (THE-215 §7). `@` opens a
   sheet of the company's agents (`showPickerSheet`) and inserts `@Name ` at
   the caret, replacing a selection. On send, each `@Name` that was picked from
   the sheet becomes `[@Name](agent://<agent id>)`, the mention format Paperclip
   uses; a name typed by hand stays plain text. Inline `@` autocomplete is
   about +1 day and not built.
6. **One column, not a lazy list.** The thread is a `Column` in a scroll view,
   so every loaded comment is laid out and the scroll extent is exact. That is
   what keeps the view still when "Load earlier" adds a page above it and lets
   the screen open exactly at the last comment. Pages of 50 bound the cost; a
   lazy list would need an anchor-based scroll fix that is not worth it here.
7. **Markdown** comes from `AppMarkdown` (PR 2a, merged): safe subset, links
   open in the system browser, images are placeholders, an `agent://` link
   shows as plain `@Name`.
8. **Row-tap.** `itemTarget` sends a row that links to an issue to S6, so the
   Inbox opens the issue instead of the browser. A fragment or an `interactions`
   path is an in-thread target and keeps the browser stopgap until S5.
   Questions (`issue_thread_interaction`) also keep it.
9. **Reading changes nothing** (AC9): S6 only issues `GET`s plus the reply
   `POST`. There is no status or assignee editing.
10. **Closed issues** (AC8) stay readable and keep the reply bar. A note says
   the server decides; a refusal shows as "Not sent" with the server message.

## Consequences

- Comment authors that are people show as "You" (the signed-in user) or "Board
  user". The API gives no display names for other people.
- `AppPill` now shortens a long label instead of overflowing its row.
- The POST answer fixture is synthesized (recording it would have written to a
  real issue). Everything else in `issue*.json` is recorded and scrubbed.
- The linked-issue row on S4 still opens the browser. Pointing it at S6 needs
  its own small change and test update (follow-up, not this PR).

## Reopen if

Threads regularly exceed a few hundred loaded comments (switch to a lazy list
with an anchor), or the server adds a `before` cursor or a comment count.
Revisit the Edit scan window if the server adds a lookup by `clientRequestId`.
