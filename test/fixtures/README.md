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

## The other fixtures are synthesized

`companies.json`, `agents.json`, `health.json`, `session_me.json` follow the
API map in the feasibility note and were not recorded. They are small and
stable; replace them the same way if a payload changes.

## Demo data is separate

`lib/data/fake/demo_data.dart` is invented demo content. It still covers all
11 `sourceKind`s plus one unknown kind, so demo mode and tolerance tests do not
depend on the recorded fixture.
