import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/ui/ui.dart';

import '../support/app_harness.dart';

void main() {
  void usePhone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('PickerChip is one labelled 44 pt button', (tester) async {
    usePhone(tester);
    var taps = 0;
    await tester.pumpWidget(
      themed(
        Center(
          child: PickerChip(
            label: 'Assignee',
            value: 'Chief Example',
            onTap: () => taps++,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Assignee: Chief Example'), findsOneWidget);
    expect(
      tester.getSize(find.byType(PickerChip)).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.byType(PickerChip));
    expect(taps, 1);
  });

  testWidgets('a disabled chip ignores taps', (tester) async {
    await tester.pumpWidget(
      themed(
        const Center(
          child: PickerChip(label: 'Project', value: 'None', onTap: null),
        ),
      ),
    );
    await tester.tap(find.byType(PickerChip), warnIfMissed: false);
    // No crash and no sheet: nothing to assert beyond the widget being there.
    expect(find.byType(PickerChip), findsOneWidget);
  });

  Future<PickerChoice<String>?> openSheet(
    WidgetTester tester, {
    List<PickerOption<String>> options = const [
      PickerOption(value: 'a', label: 'Alpha', subtitle: 'ceo'),
      PickerOption(value: 'b', label: 'Beta'),
    ],
    String? selected,
    String? noneLabel,
  }) async {
    usePhone(tester);
    PickerChoice<String>? result;
    var done = false;
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showPickerSheet<String>(
                  context: context,
                  title: 'Pick one',
                  options: options,
                  selected: selected,
                  noneLabel: noneLabel,
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Pick one'), findsOneWidget);
    expect(done, isFalse);
    return result;
  }

  testWidgets('tapping a row returns it and closes the sheet', (tester) async {
    PickerChoice<String>? result;
    usePhone(tester);
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => result = await showPickerSheet<String>(
                context: context,
                title: 'Pick one',
                options: const [
                  PickerOption(value: 'a', label: 'Alpha', subtitle: 'ceo'),
                  PickerOption(value: 'b', label: 'Beta'),
                ],
                selected: 'a',
                noneLabel: 'None',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ceo'), findsOneWidget);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    expect(result?.value, 'b');
    expect(find.text('Pick one'), findsNothing);
  });

  testWidgets('the none row returns a null value, not a dismissal', (
    tester,
  ) async {
    PickerChoice<String>? result;
    usePhone(tester);
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => result = await showPickerSheet<String>(
                context: context,
                title: 'Pick one',
                options: const [PickerOption(value: 'a', label: 'Alpha')],
                noneLabel: 'None',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.value, isNull);
  });

  testWidgets('an empty list says so', (tester) async {
    await openSheet(tester, options: const []);
    expect(find.text('Nothing to choose from.'), findsOneWidget);
  });
}
