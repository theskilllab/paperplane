# lib/app

App shell. `app.dart` is the root widget, `router.dart` declares every route
(S1 is built; S4–S7 are stubs until a later PR), `routes.dart` holds the paths,
`providers.dart` wires `ApiClient` and the repositories, and `app_env.dart`
holds the demo flag (`--dart-define=PAPERPLANE_DEMO=true`).

When you build a screen, replace its `StubScreen` in `router.dart`. Link to
other screens with the helpers in `routes.dart`.
