import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/ui/ui.dart';

import 'support/app_harness.dart';

/// One golden per component, default state only. Error, empty, loading and
/// pressed states are covered by widget tests (`test/ui/`), not images.
///
/// Text renders in the test font (Ahem blocks), so a golden checks surface,
/// shape, spacing and layout, not glyphs. Run with `--update-goldens` after an
/// intended change and review the image in the diff.
Future<void> golden(
  WidgetTester tester,
  String name,
  Widget child, {
  Size size = const Size(390, 200),
  bool reduceMotion = true,
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    themed(
      RepaintBoundary(
        key: const Key('golden'),
        child: ColoredBox(
          color: Colors.white,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
      reduceMotion: reduceMotion,
    ),
  );
  // Let flutter_svg finish parsing before the image is taken.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  testWidgets('AppButton', (tester) async {
    await golden(
      tester,
      'app_button',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final style in AppButtonStyle.values) ...[
            AppButton(label: style.name, style: style, onPressed: () {}),
            const SizedBox(height: 8),
          ],
        ],
      ),
      size: const Size(390, 260),
    );
  });

  testWidgets('AppIconButton', (tester) async {
    await golden(
      tester,
      'app_icon_button',
      Row(
        children: [
          AppIconButton(
            icon: AppIconName.back,
            semanticLabel: 'Back',
            onPressed: () {},
          ),
          AppIconButton(
            icon: AppIconName.plus,
            semanticLabel: 'New',
            onPressed: () {},
          ),
        ],
      ),
      size: const Size(390, 80),
    );
  });

  testWidgets('AppTextField', (tester) async {
    await golden(
      tester,
      'app_text_field',
      const AppTextField(
        label: 'Server address',
        required: true,
        help: 'Include https://',
      ),
      size: const Size(390, 140),
    );
  });

  testWidgets('AppErrorText', (tester) async {
    await golden(
      tester,
      'app_error_text',
      const AppErrorText('Include https:// in the address.'),
      size: const Size(390, 70),
    );
  });

  testWidgets('AppCardList, AppListRow and AppGroupHeader', (tester) async {
    await golden(
      tester,
      'app_card_list',
      const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppGroupHeader('Approvals', count: 2),
          AppCardList(
            children: [
              AppListRow(
                title: 'Hire a support agent',
                meta: Text('ACM-1 · 12 min ago'),
                leading: AppStatusIcon(AppStatus.review),
                unread: true,
                chevron: true,
                tall: true,
              ),
              AppListRow(
                title: 'Raise the monthly budget limit',
                meta: Text('ACM-2 · 3 h ago'),
                leading: AppStatusIcon(AppStatus.todo),
                chevron: true,
                tall: true,
              ),
            ],
          ),
        ],
      ),
      size: const Size(390, 270),
    );
  });

  testWidgets('AppPill', (tester) async {
    await golden(
      tester,
      'app_pill',
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tone in AppPillTone.values)
            AppPill(tone.name, tone: tone, icon: AppIconName.check),
        ],
      ),
      size: const Size(390, 100),
    );
  });

  testWidgets('AppBanner', (tester) async {
    await golden(
      tester,
      'app_banner',
      Column(
        children: [
          for (final kind in AppBannerKind.values) ...[
            AppBanner(
              kind: kind,
              title: kind.name,
              message: 'Short explanation of what happened.',
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
      size: const Size(390, 440),
    );
  });

  testWidgets('AppSkeletonRow', (tester) async {
    await golden(
      tester,
      'app_skeleton_row',
      const AppSkeletonRow(),
      size: const Size(390, 110),
    );
  });

  testWidgets('AppEmptyState', (tester) async {
    await golden(
      tester,
      'app_empty_state',
      const SizedBox(
        height: 220,
        child: AppEmptyState(
          title: 'Nothing needs you',
          message: 'New requests show up here.',
        ),
      ),
      size: const Size(390, 260),
    );
  });

  testWidgets('AppNavBar', (tester) async {
    await golden(
      tester,
      'app_nav_bar',
      Material(
        child: SizedBox(
          height: 160,
          child: Column(
            children: [
              AppNavBar(title: 'abc-12', onBack: () {}),
              const AppNavBar(largeTitle: 'Inbox'),
            ],
          ),
        ),
      ),
    );
  });

  testWidgets('AppStatusIcon', (tester) async {
    await golden(
      tester,
      'app_status_icon',
      Wrap(
        spacing: 12,
        children: [for (final s in AppStatus.values) AppStatusIcon(s)],
      ),
      size: const Size(390, 70),
    );
  });

  testWidgets('AppGhostAvatar and AppInitialsAvatar', (tester) async {
    await golden(
      tester,
      'app_avatar',
      Wrap(
        spacing: 8,
        children: [
          for (var i = 0; i < 8; i++) AppGhostAvatar('agent-$i', size: 32),
          const AppInitialsAvatar('Ada Example'),
        ],
      ),
      size: const Size(390, 80),
    );
  });

  testWidgets('AppIcon set', (tester) async {
    await golden(
      tester,
      'app_icons',
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final n in AppIconName.values) AppIcon(n)],
      ),
      size: const Size(390, 110),
    );
  });

  testWidgets('AppToast', (tester) async {
    await golden(
      tester,
      'app_toast',
      const AppToast(message: 'Approved'),
      size: const Size(390, 90),
    );
  });

  testWidgets('AppSheet content', (tester) async {
    await golden(
      tester,
      'app_sheet',
      AppSheet(
        title: 'Switch company',
        child: AppButton(label: 'Done', onPressed: () {}, block: true),
      ),
      size: const Size(390, 170),
    );
  });

  testWidgets('AppTabBar', (tester) async {
    await golden(
      tester,
      'app_tab_bar',
      Material(
        child: AppTabBar(
          destinations: const [
            AppTabDestination(icon: Icons.inbox_outlined, label: 'Inbox'),
            AppTabDestination(icon: Icons.settings_outlined, label: 'Settings'),
          ],
          currentIndex: 0,
          onSelected: (_) {},
        ),
      ),
      size: const Size(390, 120),
    );
  });
}
