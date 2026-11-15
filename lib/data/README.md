# lib/data

One file per feature, so parallel PRs do not conflict. Each file has an
abstract repository, an `Http…` implementation over `ApiClient`, and (in
`fake/fake_repositories.dart`) a `Fake…` one that serves demo data. Providers
in `lib/app/providers.dart` pick the Fake in demo mode and in tests.

`auth_repository.dart` is the pre-session exception: it handles sign-in,
paste-token verification and device login, so it cannot use the signed-in
`ApiClient` provider. The Inbox and company repositories also keep the last
server answer in preferences for a cold start without network; sign-out and a
company switch clear it.

Adding a repository:

1. Add `foo_repository.dart` with `abstract interface class FooRepository`
   and `HttpFooRepository(ApiClient)`.
2. Add `FakeFooRepository` to `fake/fake_repositories.dart` (use the
   `FakeBehavior` mixin for latency and forced errors) and its data to
   `fake/demo_data.dart`.
3. Add its provider to `lib/app/providers.dart`.
4. Add a fixture to `test/fixtures/` and a parse test.

Decision calls (approve, reject, answer) pass `stateConflict: true` to
`ApiClient.post` so 409 and 422 become `AlreadyHandled`.
