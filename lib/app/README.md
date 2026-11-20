# lib/app

App shell. `app.dart` is the root widget, `router.dart` declares every route
(S1, S2, S3, S4, S6 and S7 are built; S5 is a stub until a later PR), `routes.dart` holds the paths,
`providers.dart` wires `ApiClient` and the repositories, and `app_env.dart`
holds the demo flag (`--dart-define=PAPERPLANE_DEMO=true`).

When you build a screen, replace its `StubScreen` in `router.dart`. Link to
other screens with the helpers in `routes.dart`.
