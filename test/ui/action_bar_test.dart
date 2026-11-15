import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/ui/ui.dart';

import '../support/app_harness.dart';

void main() {
  testWidgets('actions share the width and each can be tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      themed(
        Column(
          children: [
            const Spacer(),
            AppActionBar(
              children: [
                AppButton(
                  label: 'Reject',
                  style: AppButtonStyle.secondary,
                  onPressed: () {},
                ),
                AppButton(label: 'Approve', onPressed: () => taps++),
              ],
            ),
          ],
        ),
      ),
    );

    final reject = tester.getSize(find.text('Reject').first);
    final approve = tester.getSize(find.text('Approve').first);
    expect(reject.width, greaterThan(0));
    expect(approve.width, greaterThan(0));

    final buttons = find.byType(AppButton);
    expect(
      tester.getSize(buttons.at(0)).width,
      tester.getSize(buttons.at(1)).width,
    );

    await tester.tap(find.text('Approve'));
    expect(taps, 1);
  });

  testWidgets('the bar spans the screen while its actions stay in 640', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(820, 1180) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      themed(
        Column(
          children: [
            const Spacer(),
            AppActionBar(
              children: [
                AppButton(label: 'Reject', onPressed: () {}),
                AppButton(label: 'Approve', onPressed: () {}),
              ],
            ),
          ],
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppActionBar)).width, 820);
    final buttons = find.byType(AppButton);
    final left = tester.getTopLeft(buttons.at(0)).dx;
    final right = tester.getBottomRight(buttons.at(1)).dx;
    expect(right - left, lessThanOrEqualTo(640));
    expect(left, greaterThan(80));
  });

  testWidgets('long values wrap at 360 pt with XXL text', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPaperplaneTheme(),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: AppKeyValueCard(
                rows: [
                  AppKeyValue('Role', 'engineer'),
                  AppKeyValue(
                    'A long label that wraps',
                    'A long value that wraps over several lines on a phone',
                    icon: AppIconName.server,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Role'), findsOneWidget);
    expect(find.text('engineer'), findsOneWidget);
    expect(find.textContaining('A long value'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each key/value row reads as one line', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      themed(const AppKeyValueCard(rows: [AppKeyValue('Role', 'engineer')])),
    );

    expect(find.bySemanticsLabel('Role: engineer'), findsOneWidget);
    handle.dispose();
  });
}
