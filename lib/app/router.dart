import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:paperplane/app/route_observer.dart';
import 'package:paperplane/app/routes.dart';
import 'package:paperplane/app/stub_screen.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/features/connect/connect_screen.dart';
import 'package:paperplane/features/inbox/inbox_screen.dart';

/// Where [session] sends the user from [location], or null to stay.
///
/// - Restoring: wait on the splash screen.
/// - Signed out: S1 only (PRD G3 lands here with the address prefilled).
/// - Signed in: everything except S1 and the splash.
@visibleForTesting
String? redirectFor(SessionState session, String location) {
  switch (session) {
    case SessionRestoring():
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case SignedOut():
      return location == AppRoutes.connect ? null : AppRoutes.connect;
    case SignedIn():
      return location == AppRoutes.connect || location == AppRoutes.splash
          ? AppRoutes.inbox
          : null;
  }
}

/// The app's router. S2 is built; S3 is a sheet over S2, so it has no route.
/// Screens that no PR has built yet are `StubScreen`s.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(sessionControllerProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.inbox,
    refreshListenable: refresh,
    observers: [appRouteObserver],
    redirect: (context, state) =>
        redirectFor(ref.read(sessionControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: AppRoutes.connect,
        builder: (context, state) => const ConnectScreen(),
      ),
      GoRoute(
        path: AppRoutes.inbox,
        builder: (context, state) => const InboxScreen(),
        routes: [
          GoRoute(
            path: AppRoutes.approvalPattern.substring(1),
            builder: (context, state) =>
                const StubScreen(screen: 'S4 Approval', builtIn: 'PR 2'),
          ),
          GoRoute(
            path: AppRoutes.newIssue.substring(1),
            builder: (context, state) =>
                const StubScreen(screen: 'S7 New issue', builtIn: 'PR 3'),
          ),
          GoRoute(
            path: AppRoutes.interactionPattern.substring(1),
            builder: (context, state) =>
                const StubScreen(screen: 'S5 Question', builtIn: 'PR 2'),
          ),
          GoRoute(
            path: AppRoutes.issuePattern.substring(1),
            builder: (context, state) =>
                const StubScreen(screen: 'S6 Issue', builtIn: 'PR 3'),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
