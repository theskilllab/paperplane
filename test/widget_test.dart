import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/app.dart';

void main() {
  testWidgets('shows the inbox tab and switches to settings', (tester) async {
    await tester.pumpWidget(const PaperplaneApp());

    expect(find.text('Inbox'), findsWidgets);

    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(find.text('Settings'), findsWidgets);
  });
}
