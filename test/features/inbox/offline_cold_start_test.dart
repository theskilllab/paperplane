import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/app/app.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/app_harness.dart';
import '../../support/fake_adapter.dart';

/// Full stack (real repositories, real prefs, fake HTTP adapter): the Inbox the
/// user saw online must be on screen at once on the next start, offline or
/// with a network that never answers (PRD S1 AC11, G2).
void main() {
  const base = 'https://paperclip.example.test';
  final now = DateTime.utc(2026, 11, 12, 12);

  ResponseBody answer(RequestOptions o) {
    if (o.path.endsWith('/companies')) return jsonBody(demoCompaniesJson);
    if (o.path.endsWith('/attention')) return jsonBody(demoAttentionJson(now));
    return jsonBody(<Object?>[]); // agents
  }

  Future<ProviderContainer> start(
    WidgetTester tester,
    FakeAdapter adapter,
    Map<String, Object> prefs,
  ) async {
    tester.view
      ..physicalSize = const Size(780, 1688)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...await appOverrides(prefs: prefs, keys: {base: 'fake-key'}),
        httpAdapterProvider.overrideWithValue(adapter),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PaperplaneApp(),
      ),
    );
    return container;
  }

  /// Runs one online start, then returns what is left on disk.
  Future<Map<String, Object>> onlineRun(WidgetTester tester) async {
    await start(tester, FakeAdapter((o) async => answer(o)), {
      'last_base_url': base,
    });
    await tester.pumpAndSettle();
    expect(find.text('Hire a support agent'), findsOneWidget);
    final disk = await SharedPreferences.getInstance();
    return {for (final k in disk.getKeys()) k: disk.get(k)!};
  }

  Future<ResponseBody> offline(RequestOptions o) => Future.error(
    DioException(
      requestOptions: o,
      type: DioExceptionType.connectionError,
      error: const SocketException('Network is unreachable'),
    ),
  );

  testWidgets('offline cold start: cached rows and offline banner', (
    tester,
  ) async {
    final disk = await onlineRun(tester);
    await tester.pumpWidget(const SizedBox());

    await start(tester, FakeAdapter(offline), disk);
    await tester.pumpAndSettle();

    expect(find.byType(AppSkeletonRow), findsNothing);
    expect(find.text('Hire a support agent'), findsOneWidget);
    expect(find.byType(AppBanner), findsOneWidget);
    expect(find.textContaining('Last updated'), findsOneWidget);
  });

  testWidgets('cold start on a network that never answers: cached rows at '
      'once, no skeleton', (tester) async {
    final disk = await onlineRun(tester);
    await tester.pumpWidget(const SizedBox());

    final hang = Completer<ResponseBody>();
    addTearDown(() {
      if (!hang.isCompleted) hang.completeError(StateError('test over'));
    });
    await start(tester, FakeAdapter((_) => hang.future), disk);
    // A few frames for session restore and the cache reads, far below the
    // 15 s request timeout.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(AppSkeletonRow), findsNothing);
    expect(find.text('Hire a support agent'), findsOneWidget);
  });
}
