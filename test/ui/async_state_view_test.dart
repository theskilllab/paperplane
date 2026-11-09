import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/ui/ui.dart';

import '../support/app_harness.dart';

Widget view(
  AsyncValue<List<String>> value, {
  VoidCallback? onRetry,
  VoidCallback? onBack,
  DateTime? lastUpdated,
  bool Function(List<String>)? isEmpty,
}) => themed(
  AsyncStateView<List<String>>(
    value: value,
    host: 'paperclip.example.test',
    lastUpdated: lastUpdated,
    onRetry: onRetry,
    onBack: onBack,
    isEmpty: isEmpty,
    builder: (context, rows) =>
        ListView(children: [for (final r in rows) ListTile(title: Text(r))]),
  ),
);

/// What a screen really sees after a refresh failed: produced by a provider,
/// not built by hand, so it matches production exactly.
Future<AsyncValue<List<String>>> staleWith(
  WidgetTester tester,
  ApiError error, {
  List<String> rows = const ['Old row'],
}) async => (await tester.runAsync(() => _staleWith(error, rows)))!;

Future<AsyncValue<List<String>>> _staleWith(
  ApiError error,
  List<String> rows,
) async {
  var calls = 0;
  final provider = FutureProvider<List<String>>((ref) async {
    if (calls++ == 0) return rows;
    throw error;
  });
  final container = ProviderContainer(retry: (_, _) => null);
  addTearDown(container.dispose);
  container.listen(provider, (_, _) {});
  await container.read(provider.future);
  await expectLater(container.refresh(provider.future), throwsA(error));
  final value = container.read(provider);
  expect(value.hasValue && value.hasError, isTrue);
  return value;
}

void main() {
  testWidgets('G1: first load shows skeleton rows, not a blank screen', (
    tester,
  ) async {
    await tester.pumpWidget(view(const AsyncLoading()));
    expect(find.byType(AppSkeletonRow), findsNWidgets(3));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('data renders through the builder', (tester) async {
    await tester.pumpWidget(view(const AsyncData(['A', 'B'])));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.byType(AppSkeletonRow), findsNothing);
  });

  testWidgets('a refresh keeps the old data and shows no banner', (
    tester,
  ) async {
    final gate = Completer<List<String>>();
    final value = (await tester.runAsync(() async {
      var calls = 0;
      final provider = FutureProvider<List<String>>((ref) {
        if (calls++ == 0) return ['Old row'];
        return gate.future;
      });
      final container = ProviderContainer(retry: (_, _) => null);
      addTearDown(container.dispose);
      container.listen(provider, (_, _) {});
      await container.read(provider.future);
      // The refresh stays pending on purpose.
      container.refresh(provider);
      return container.read(provider);
    }))!;
    expect(value.isLoading && value.hasValue, isTrue);

    await tester.pumpWidget(view(value));
    expect(find.text('Old row'), findsOneWidget);
    expect(find.byType(AppBanner), findsNothing);
    gate.complete(const []);
  });

  testWidgets('empty data shows the empty state', (tester) async {
    await tester.pumpWidget(
      view(const AsyncData(<String>[]), isEmpty: (rows) => rows.isEmpty),
    );
    expect(find.text('Nothing here'), findsOneWidget);
  });

  group('error without data', () {
    testWidgets('G2: offline shows "Can\'t reach {host}" and Retry', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        view(
          const AsyncError(Offline(), StackTrace.empty),
          onRetry: () => retries++,
        ),
      );
      expect(find.text("Can't reach paperclip.example.test"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('timeouts read the same as offline', (tester) async {
      await tester.pumpWidget(
        view(const AsyncError(TimedOut(), StackTrace.empty), onRetry: () {}),
      );
      expect(find.text("Can't reach paperclip.example.test"), findsOneWidget);
    });

    testWidgets('G4: 403 shows no-access and Back, never Retry', (
      tester,
    ) async {
      var backs = 0;
      await tester.pumpWidget(
        view(
          const AsyncError(Forbidden('secret server text'), StackTrace.empty),
          onRetry: () {},
          onBack: () => backs++,
        ),
      );
      expect(find.text("You don't have access to this"), findsOneWidget);
      expect(find.text('secret server text'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.text('Back'));
      expect(backs, 1);
    });

    testWidgets('G3: 401 says the session expired, with no button', (
      tester,
    ) async {
      await tester.pumpWidget(
        view(
          const AsyncError(Unauthorized(), StackTrace.empty),
          onRetry: () {},
        ),
      );
      expect(find.text('Your session expired'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('G5: server error shows the status code and Retry', (
      tester,
    ) async {
      await tester.pumpWidget(
        view(const AsyncError(Server(502), StackTrace.empty), onRetry: () {}),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Error 502'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a non-ApiError is still handled, with no stack shown', (
      tester,
    ) async {
      await tester.pumpWidget(
        view(
          AsyncError(StateError('boom'), StackTrace.current),
          onRetry: () {},
        ),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('no Retry button without a callback', (tester) async {
      await tester.pumpWidget(
        view(const AsyncError(Server(500), StackTrace.empty)),
      );
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('G2: error with data', () {
    testWidgets('keeps the old rows and shows "Last updated" with Retry', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        view(
          await staleWith(tester, const Offline()),
          lastUpdated: DateTime(2026, 1, 15, 14, 32),
          onRetry: () => retries++,
        ),
      );
      expect(find.text('Old row'), findsOneWidget);
      expect(find.text("Can't reach paperclip.example.test"), findsOneWidget);
      expect(find.text('Last updated 14:32'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('other errors keep the rows and show an error banner', (
      tester,
    ) async {
      await tester.pumpWidget(
        view(await staleWith(tester, const Server(500)), onRetry: () {}),
      );
      expect(find.text('Old row'), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets(
      'empty data plus an error shows the banner and the empty state',
      (tester) async {
        await tester.pumpWidget(
          view(
            await staleWith(tester, const Offline(), rows: const []),
            isEmpty: (rows) => rows.isEmpty,
          ),
        );
        expect(find.byType(AppBanner), findsOneWidget);
        expect(find.text('Nothing here'), findsOneWidget);
      },
    );
  });

  test('formatClock pads to HH:mm', () {
    expect(formatClock(DateTime(2026, 1, 1, 9, 5)), '09:05');
  });
}
