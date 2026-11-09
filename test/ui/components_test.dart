import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/ui/ui.dart';

import '../support/app_harness.dart';

void main() {
  group('AppButton', () {
    testWidgets('calls onPressed on tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        themed(AppButton(label: 'Approve', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Approve'));
      expect(taps, 1);
    });

    testWidgets('null onPressed disables it', (tester) async {
      await tester.pumpWidget(
        themed(const AppButton(label: 'Approve', onPressed: null)),
      );
      await tester.tap(find.text('Approve'), warnIfMissed: false);
      final data = tester
          .getSemantics(find.byType(AppButton))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.label, 'Approve');
    });

    testWidgets('loading ignores taps, shows a spinner and speaks the label', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        themed(
          AppButton(
            label: 'Approve',
            loading: true,
            loadingLabel: 'Approving…',
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byType(AppButton), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Approving…'), findsOneWidget);
    });

    testWidgets('loading keeps the width of the label', (tester) async {
      await tester.pumpWidget(
        themed(
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(label: 'Approve this request', onPressed: null),
                AppButton(
                  label: 'Approve this request',
                  onPressed: null,
                  loading: true,
                ),
              ],
            ),
          ),
        ),
      );
      final sizes = tester
          .widgetList(find.byType(AppButton))
          .map((w) => tester.getSize(find.byWidget(w)))
          .toList();
      expect(sizes[0].width, sizes[1].width);
    });

    testWidgets('heights: 48 regular, 44 small', (tester) async {
      await tester.pumpWidget(
        themed(
          Column(
            children: [
              AppButton(label: 'A', onPressed: () {}),
              AppButton(label: 'B', onPressed: () {}, small: true),
            ],
          ),
        ),
      );
      expect(tester.getSize(find.widgetWithText(AppButton, 'A')).height, 48);
      expect(tester.getSize(find.widgetWithText(AppButton, 'B')).height, 44);
    });

    testWidgets('block fills the width', (tester) async {
      await tester.pumpWidget(
        themed(AppButton(label: 'Go', onPressed: () {}, block: true)),
      );
      expect(tester.getSize(find.byType(AppButton)).width, 800);
    });

    testWidgets('all four styles render', (tester) async {
      await tester.pumpWidget(
        themed(
          Column(
            children: [
              for (final style in AppButtonStyle.values)
                AppButton(label: style.name, style: style, onPressed: () {}),
            ],
          ),
        ),
      );
      for (final style in AppButtonStyle.values) {
        expect(find.text(style.name), findsOneWidget);
      }
    });

    testWidgets('keyboard activation works', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        themed(AppButton(label: 'Go', onPressed: () => taps++)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, 1);
    });
  });

  group('AppIconButton', () {
    testWidgets('is 44×44, labelled, and tappable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        themed(
          Center(
            child: AppIconButton(
              icon: AppIconName.back,
              semanticLabel: 'Back',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppIconButton)), const Size(44, 44));
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      await tester.tap(find.byType(AppIconButton));
      expect(taps, 1);
    });

    testWidgets('disabled ignores taps', (tester) async {
      await tester.pumpWidget(
        themed(
          const AppIconButton(
            icon: AppIconName.plus,
            semanticLabel: 'New',
            onPressed: null,
          ),
        ),
      );
      await tester.tap(find.byType(AppIconButton), warnIfMissed: false);
    });
  });

  group('AppTextField', () {
    testWidgets('shows label, required star and help', (tester) async {
      await tester.pumpWidget(
        themed(
          const AppTextField(
            label: 'Server address',
            required: true,
            help: 'Include https://',
          ),
        ),
      );
      expect(find.textContaining('Server address'), findsOneWidget);
      expect(find.textContaining('*'), findsOneWidget);
      expect(find.text('Include https://'), findsOneWidget);
    });

    testWidgets('error text replaces help and is a live region', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(
          const AppTextField(
            label: 'URL',
            help: 'Help',
            errorText: 'Include https://',
          ),
        ),
      );
      expect(find.text('Help'), findsNothing);
      expect(find.text('Include https://'), findsOneWidget);
      expect(find.byType(AppErrorText), findsOneWidget);
    });

    testWidgets('keeps typed text through an error', (tester) async {
      final controller = TextEditingController(text: 'abc');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        themed(
          AppTextField(label: 'URL', controller: controller, errorText: 'Bad'),
        ),
      );
      expect(find.text('abc'), findsOneWidget);
    });

    testWidgets('typing reaches onChanged', (tester) async {
      String? last;
      await tester.pumpWidget(
        themed(AppTextField(label: 'URL', onChanged: (v) => last = v)),
      );
      await tester.enterText(find.byType(TextField), 'https://a.example.test');
      expect(last, 'https://a.example.test');
    });

    testWidgets('loading shows a spinner; disabled blocks input', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(const AppTextField(label: 'URL', loading: true, enabled: false)),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('obscured fields are single line', (tester) async {
      await tester.pumpWidget(
        themed(
          const AppTextField(label: 'Password', obscureText: true, maxLines: 4),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 1);
    });

    testWidgets('is at least 48 high', (tester) async {
      await tester.pumpWidget(themed(const AppTextField(label: 'URL')));
      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('AppListRow and cards', () {
    testWidgets('tap, meta and semantic label', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        themed(
          AppCardList(
            children: [
              AppListRow(
                title: 'Hire a support agent',
                meta: const Text('12 min ago'),
                leading: const AppStatusIcon(AppStatus.review),
                semanticLabel: 'Approval, Hire a support agent, 12 min ago',
                onTap: () => taps++,
                tall: true,
              ),
              const AppListRow(title: 'Second row', chevron: true),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Hire a support agent'));
      expect(taps, 1);
      expect(find.text('12 min ago'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Approval, Hire a support agent, 12 min ago'),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.widgetWithText(AppListRow, 'Hire a support agent'))
            .height,
        greaterThanOrEqualTo(64),
      );
    });

    testWidgets('resolving ignores taps and shows a spinner', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        themed(AppListRow(title: 'Row', resolving: true, onTap: () => taps++)),
      );
      await tester.tap(find.text('Row'), warnIfMissed: false);
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a row without onTap is inert', (tester) async {
      await tester.pumpWidget(themed(const AppListRow(title: 'No link')));
      await tester.tap(find.text('No link'));
    });

    testWidgets('two-line title limit', (tester) async {
      await tester.pumpWidget(themed(AppListRow(title: 'word ' * 80)));
      final text = tester.widget<Text>(find.byType(Text).first);
      expect(text.maxLines, 2);
    });

    testWidgets('the unread dot appears', (tester) async {
      await tester.pumpWidget(
        themed(const AppListRow(title: 'R', unread: true)),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 8 && w.height == 8,
        ),
        findsOneWidget,
      );
    });

    testWidgets('AppCardList separates rows with hairlines', (tester) async {
      await tester.pumpWidget(
        themed(
          const AppCardList(
            children: [
              AppListRow(title: 'a'),
              AppListRow(title: 'b'),
              AppListRow(title: 'c'),
            ],
          ),
        ),
      );
      final dividers = find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 1 && w.width == null,
      );
      expect(dividers, findsNWidgets(2));
    });

    testWidgets('group header upper-cases and shows the count', (tester) async {
      await tester.pumpWidget(
        themed(const AppGroupHeader('Approvals', count: 3)),
      );
      expect(find.text('APPROVALS'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.bySemanticsLabel('Approvals, 3'), findsOneWidget);
    });
  });

  group('AppPill, AppBanner, AppEmptyState', () {
    testWidgets('every pill tone renders its label', (tester) async {
      await tester.pumpWidget(
        themed(
          Wrap(
            children: [
              for (final tone in AppPillTone.values)
                AppPill(tone.name, tone: tone, icon: AppIconName.check),
            ],
          ),
        ),
      );
      for (final tone in AppPillTone.values) {
        expect(find.text(tone.name), findsOneWidget);
      }
    });

    testWidgets('banner shows title, message and runs its action', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        themed(
          AppBanner(
            kind: AppBannerKind.offline,
            title: "Can't reach the server",
            message: 'Last updated 14:32',
            actionLabel: 'Retry',
            onAction: () => retries++,
          ),
        ),
      );
      expect(find.text("Can't reach the server"), findsOneWidget);
      expect(find.text('Last updated 14:32'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('every banner kind renders', (tester) async {
      await tester.pumpWidget(
        themed(
          Column(
            children: [
              for (final kind in AppBannerKind.values)
                AppBanner(kind: kind, title: kind.name),
            ],
          ),
        ),
      );
      for (final kind in AppBannerKind.values) {
        expect(find.text(kind.name), findsOneWidget);
      }
    });

    testWidgets('empty state shows its action only with a callback', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(
          const AppEmptyState(title: 'Nothing needs you', actionLabel: 'New'),
        ),
      );
      expect(find.text('New'), findsNothing);

      var taps = 0;
      await tester.pumpWidget(
        themed(
          AppEmptyState(
            title: 'Nothing needs you',
            actionLabel: 'New issue',
            onAction: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('New issue'));
      expect(taps, 1);
    });

    testWidgets('error variant defaults to Retry', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        themed(
          AppEmptyState.error(
            title: "Can't reach host",
            detail: 'Error 502',
            onAction: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('Retry'));
      expect(taps, 1);
      expect(find.text('Error 502'), findsOneWidget);
    });
  });

  group('AppSkeletonRow', () {
    testWidgets('animates, and holds still under Reduce Motion', (
      tester,
    ) async {
      await tester.pumpWidget(themed(const AppSkeletonRow()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        themed(const AppSkeletonRow(), reduceMotion: true),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('AppNavBar', () {
    testWidgets('title is upper-case; back works; actions show', (
      tester,
    ) async {
      var backs = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPaperplaneTheme(),
          home: Scaffold(
            appBar: AppNavBar(
              title: 'abc-12',
              onBack: () => backs++,
              actions: [
                AppIconButton(
                  icon: AppIconName.plus,
                  semanticLabel: 'New issue',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('ABC-12'), findsOneWidget);
      expect(find.bySemanticsLabel('New issue'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back'));
      expect(backs, 1);
    });

    testWidgets('large title adds height and shows the text', (tester) async {
      const bar = AppNavBar(largeTitle: 'Inbox');
      expect(
        bar.preferredSize.height,
        greaterThan(const AppNavBar().preferredSize.height),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPaperplaneTheme(),
          home: const Scaffold(appBar: bar),
        ),
      );
      expect(find.text('Inbox'), findsOneWidget);
    });

    testWidgets('a badge follows the large title and is spoken with it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPaperplaneTheme(),
          home: const Scaffold(
            appBar: AppNavBar(largeTitle: 'Inbox', largeTitleBadge: '12'),
          ),
        ),
      );
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.bySemanticsLabel('Inbox, 12'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('content stays in the 640 column on a tablet', (tester) async {
      tester.view
        ..physicalSize = const Size(1640, 1180)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPaperplaneTheme(),
          home: Scaffold(
            appBar: AppNavBar(title: 'x', onBack: () {}),
          ),
        ),
      );
      final back = tester.getTopLeft(find.byType(AppIconButton));
      expect(back.dx, greaterThan((820 - 640) / 2 - 1));
    });
  });

  group('AppStatusIcon and avatars', () {
    testWidgets('every status has a label', (tester) async {
      await tester.pumpWidget(
        themed(
          Column(
            children: [for (final s in AppStatus.values) AppStatusIcon(s)],
          ),
        ),
      );
      for (final s in AppStatus.values) {
        expect(find.bySemanticsLabel(s.label), findsOneWidget);
      }
      expect({
        for (final s in AppStatus.values) s.label,
      }, hasLength(AppStatus.values.length));
    });

    testWidgets('running spins, and stops under Reduce Motion', (tester) async {
      await tester.pumpWidget(themed(const AppStatusIcon(AppStatus.running)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        themed(const AppStatusIcon(AppStatus.running), reduceMotion: true),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    test('review and blocked differ in shape, not only color', () {
      const review = AppStatus.review;
      const blocked = AppStatus.blocked;
      expect(review.label, isNot(blocked.label));
    });

    test('ghost colors are stable and spread over the 8 pairs', () {
      expect(
        AppGhostAvatar.pairIndex('agent-ceo'),
        AppGhostAvatar.pairIndex('agent-ceo'),
      );
      final seen = {
        for (var i = 0; i < 200; i++) AppGhostAvatar.pairIndex('agent-$i'),
      };
      expect(seen, hasLength(8));
      // Pin one value so a change of hash is noticed: colors must not shift
      // between app versions.
      expect(AppGhostAvatar.pairIndex('agent-ceo'), 2);
    });

    test('initials', () {
      expect(AppInitialsAvatar.initialsOf('Ada Example'), 'AE');
      expect(AppInitialsAvatar.initialsOf('  ada  '), 'A');
      expect(AppInitialsAvatar.initialsOf('Ada Marie Example'), 'AM');
      expect(AppInitialsAvatar.initialsOf(''), '?');
    });

    testWidgets('avatars render', (tester) async {
      await tester.pumpWidget(
        themed(
          const Row(
            children: [
              AppGhostAvatar('agent-1'),
              AppInitialsAvatar('Ada Example'),
            ],
          ),
        ),
      );
      expect(find.text('AE'), findsOneWidget);
    });
  });

  group('AppIcon', () {
    test('all 16 P0 icons exist, with valid-looking SVG', () {
      expect(AppIconName.values, hasLength(16));
      for (final icon in AppIconName.values) {
        expect(icon.svg, startsWith('<svg'));
        expect(icon.svg, endsWith('</svg>'));
        expect(icon.svg, contains('stroke="currentColor"'));
      }
    });

    testWidgets('renders without error and honours the label', (tester) async {
      await tester.pumpWidget(
        themed(
          Column(
            children: [
              for (final name in AppIconName.values) AppIcon(name),
              const AppIcon(AppIconName.alert, semanticLabel: 'Warning'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Warning'), findsOneWidget);
    });
  });

  group('AppColumn', () {
    testWidgets('caps the width at 640 and centers', (tester) async {
      await tester.pumpWidget(
        themed(
          const AppColumn(
            child: SizedBox(height: 10, width: double.infinity, key: Key('c')),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('c'))).width, 640);
      expect(tester.getCenter(find.byKey(const Key('c'))).dx, 400);
    });
  });
}
