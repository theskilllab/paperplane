import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/ui/ui.dart';

void main() {
  testWidgets('AppButton and AppTabBar match golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(label: 'Approve', onPressed: () {}),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Reject',
                  style: AppButtonStyle.secondary,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          bottomNavigationBar: AppTabBar(
            destinations: const [
              AppTabDestination(icon: Icons.inbox_outlined, label: 'Inbox'),
              AppTabDestination(
                icon: Icons.settings_outlined,
                label: 'Settings',
              ),
            ],
            currentIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/app_ui_solid.png'),
    );
  });
}
