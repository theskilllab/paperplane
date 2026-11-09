# Test fixtures

Fake server answers for contract and widget tests. Everything is invented:
hostnames use the reserved `.invalid` TLD, names are obviously fake, and there
is no token, cookie or real address anywhere. `fixtures_hygiene_test.dart`
enforces that.

**These are synthesized, not recorded.** The shapes follow the API map in the
feasibility note (`GET /companies/{id}/attention`, `/companies`, `/health`,
`/cli-auth/me`). Nothing was run against a live server. PR 1b adds payloads
recorded from a real instance (scrubbed) and the contract test that parses
them with the same models.

`attention_feed.json` has one item for each of the 11 `sourceKind`s, plus one
kind this app version does not know, so the tolerant parsing is always
exercised.
