import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/ui/ui.dart';

import '../support/app_harness.dart';

Widget opener({
  ValueListenable<bool>? locked,
  String? errorText,
  void Function(Object?)? onResult,
}) => Builder(
  builder: (context) => Center(
    child: ElevatedButton(
      onPressed: () async {
        final result = await showAppSheet<String>(
          context: context,
          locked: locked,
          builder: (context) => AppSheet(
            title: 'Switch company',
            errorText: errorText,
            child: AppButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop('done'),
            ),
          ),
        );
        onResult?.call(result);
      },
      child: const Text('open'),
    ),
  ),
);

void usePhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('showAppSheet', () {
    testWidgets('phone: bottom sheet with title, grabber and content', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(themed(opener()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Switch company'), findsOneWidget);
      final grabber = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 40 && w.height == 5,
      );
      expect(grabber, findsOneWidget);
      // Sits at the bottom of the screen.
      expect(tester.getBottomLeft(find.byType(AppSheet)).dy, greaterThan(300));
      expect(tester.getSize(find.byType(AppSheet)).width, 390);
    });

    testWidgets('returns what the sheet pops with', (tester) async {
      usePhone(tester);
      Object? result;
      await tester.pumpWidget(themed(opener(onResult: (r) => result = r)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(result, 'done');
      expect(find.text('Switch company'), findsNothing);
    });

    testWidgets('a tap on the scrim dismisses it', (tester) async {
      usePhone(tester);
      Object? result = 'unset';
      await tester.pumpWidget(themed(opener(onResult: (r) => result = r)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Switch company'), findsNothing);
      expect(result, isNull);
    });

    testWidgets('locked: scrim tap and Back do nothing until unlocked', (
      tester,
    ) async {
      usePhone(tester);
      final locked = ValueNotifier<bool>(true);
      addTearDown(locked.dispose);
      await tester.pumpWidget(themed(opener(locked: locked)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Switch company'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Switch company'), findsOneWidget);

      locked.value = false;
      await tester.pump();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Switch company'), findsNothing);
    });

    testWidgets('shows an inline error and keeps the sheet open', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(themed(opener(errorText: "Couldn't switch")));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't switch"), findsOneWidget);
      expect(find.byType(AppErrorText), findsOneWidget);
    });

    testWidgets('is never taller than 90% of the screen', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppSheet<void>(
                context: context,
                builder: (_) => AppSheet(
                  child: Column(
                    children: [for (var i = 0; i < 60; i++) Text('row $i')],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final height = tester
          .getSize(find.byType(SingleChildScrollView).last)
          .height;
      expect(height, lessThanOrEqualTo(844 * 0.9 + 0.5));
    });

    testWidgets('tablet: centered 540 pt form sheet without a grabber', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1640, 2360)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(themed(opener()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Switch company'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 40 && w.height == 5,
        ),
        findsNothing,
      );
      final center = tester.getCenter(find.byType(AppSheet));
      expect(center.dx, closeTo(410, 1));
      expect(
        tester.getSize(find.byType(AppSheet)).width,
        lessThanOrEqualTo(540),
      );
    });

    testWidgets('tablet: locked blocks a tap outside too', (tester) async {
      tester.view
        ..physicalSize = const Size(1640, 2360)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final locked = ValueNotifier<bool>(true);
      addTearDown(locked.dispose);

      await tester.pumpWidget(themed(opener(locked: locked)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Switch company'), findsOneWidget);
    });
  });

  group('showAppToast', () {
    testWidgets('success toast shows, then disappears after 2.6 s', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      showAppToast(ctx, message: 'Approved');
      await tester.pump();
      expect(find.text('Approved'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('Approved'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Approved'), findsNothing);
    });

    testWidgets('error toast stays 5 s and its action dismisses it', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      var retries = 0;
      showAppToast(
        ctx,
        message: "Couldn't send",
        kind: AppToastKind.error,
        actionLabel: 'Retry',
        onAction: () => retries++,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.text("Couldn't send"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);
      expect(find.text("Couldn't send"), findsNothing);
    });

    testWidgets(
      'an explicit overlay shows the toast after the caller is gone',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildPaperplaneTheme(),
            home: const Scaffold(body: SizedBox()),
          ),
        );
        final overlay = Navigator.of(
          tester.element(find.byType(Scaffold)),
          rootNavigator: true,
        ).overlay!;

        showAppToast(overlay.context, overlay: overlay, message: 'Still here');
        await tester.pump();
        expect(find.text('Still here'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('a new toast replaces the old one', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      showAppToast(ctx, message: 'First');
      showAppToast(ctx, message: 'Second');
      await tester.pump();
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
      dismissAppToast();
      await tester.pump();
      expect(find.text('Second'), findsNothing);
    });

    testWidgets('is announced as a live region', (tester) async {
      await tester.pumpWidget(themed(const AppToast(message: 'Approved')));
      expect(find.bySemanticsLabel('Approved'), findsOneWidget);
    });
  });
}
