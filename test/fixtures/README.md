# Test fixtures

Fake server answers for contract and widget tests. `fixtures_hygiene_test.dart`
enforces that nothing real is committed: no key, token, cookie, real hostname,
real email domain or IP address.

## `attention_feed.json` is recorded

`attention_feed.json` is a `GET /companies/{id}/attention` payload recorded
from a real Paperclip instance (local `v2026.1106.0`, THE-203) and then
scrubbed: ids, titles, paths and timestamps are replaced with obvious fake
values. Field names, types and enum values are unchanged. `test/data/attention_contract_test.dart`
parses it with the same models the app uses.

The fixture holds no instance URL. The original redacted recording is in the
THE-203 "attention-fixtures" document.

## `approval_*.json` are recorded

`approval_pending.json`, `approval_decided.json` and `approval_issues.json`
follow `GET /approvals/{id}` and `GET /approvals/{id}/issues` recorded from a
local Paperclip instance (`v2026.1106.0`) and scrubbed: ids, names, times and
paths are replaced with obvious fake values. Field names and types are
unchanged. No pending approval existed on the recording instance, so the
`status` and decision fields in `approval_pending.json` are the recorded
decision fields with the pending values the server uses; the payload shape is
from a recorded `hire_agent` approval.

`approval_conflict.json` is the 422 body shape (`{"error": "..."}`) the server
returns for an approval that is no longer pending. It follows the source and
the feasibility note; the recording user could not change an approval without
board access.

## The other fixtures are synthesized

`companies.json`, `agents.json`, `projects.json`, `health.json`, `session_me.json` follow the
API map in the feasibility note and were not recorded. They are small and
stable; replace them the same way if a payload changes.

## Demo data is separate

`lib/data/fake/demo_data.dart` is invented demo content. It still covers all
11 `sourceKind`s plus one unknown kind, so demo mode and tolerance tests do not
depend on the recorded fixture.

## `issue*.json` are recorded (THE-423)

`issue.json` (`GET /issues/{id}`) and `issue_comments_page1.json`,
`issue_comments_page2.json`, `issue_comments_missing_anchor.json`
(`GET /issues/{id}/comments?order=desc&limit=N[&after=<id>]`) were recorded
from a real Paperclip instance (Nov 2026) and
scrubbed. Field names, types and enum values are as the server sent them.

What was changed:

- Ids, timestamps, titles, project name, comment bodies and every free-text
  value are replaced with invented values. Comment bodies are invented
  Markdown that covers headings, lists, quotes, code, links, an image and an
  `agent://` mention.
- Comment `metadata` is emptied to `{}` (it held internal authorization
  details the app does not read).
- `issue.json`: the bulky relation arrays (`relatedWork`, `workProducts`,
  `ancestors`, `documentSummaries`) are emptied and `project` is cut to four
  fields. No field the app reads was touched.
- `issue_comments_page1.json` has one `authorType: "user"` comment that was
  recorded from a different issue and spliced in, because the recorded issue
  had only agent comments.
- `issue_comments_page2.json` was fetched with `after=` the last id of page 1.
  The server's `after` cursor, with `order=desc`, returns the comments that are
  *older* than the anchor and not the anchor itself.
- `issue_comments_missing_anchor.json`: asking for `after=<an id that does not
  exist>` (which is what a deleted anchor looks like) answered **200 with an
  empty list**, not 404. The app handles that by re-reading the newest page.

The POST answer (`issue_comment_created.json`) is **synthesized**: recording it
would have created a comment on a real issue.

## `issue_created.json` is synthesized (THE-424)

`issue_created.json` is the answer to `POST /companies/{id}/issues` (S7). It is
`issue.json` with a new id, identifier, title, description and `status: "todo"`,
and it is **synthesized**: recording it would have created an issue on a real
instance. The response shape follows the same `GET /issues/{id}` contract that
`issue.json` records.
