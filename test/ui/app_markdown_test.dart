import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/ui/ui.dart';

import '../support/app_harness.dart';

void main() {
  testWidgets('renders paragraphs, headings, emphasis and lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const AppMarkdown(
          '# Release plan\n\n'
          'Ship **this** and *that*.\n\n'
          '- one\n'
          '- two\n\n'
          '1. first\n'
          '2. second\n\n'
          '> quoted\n\n'
          '`inline`\n\n'
          '```\ncode block\n```',
        ),
      ),
    );

    expect(find.text('Release plan'), findsOneWidget);
    expect(find.textContaining('Ship this and that.'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('quoted'), findsOneWidget);
    expect(find.text('inline'), findsOneWidget);
    expect(find.textContaining('code block'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('raw HTML is text, never rendered as markup', (tester) async {
    await tester.pumpWidget(
      themed(
        const AppMarkdown(
          '<script>alert(1)</script>\n\n'
          'A <b>bold</b> claim.',
        ),
      ),
    );

    expect(find.byType(RichText), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an image becomes a placeholder', (tester) async {
    await tester.pumpWidget(
      themed(const AppMarkdown('![a chart](https://x.example.test/a.png)')),
    );

    expect(find.text('[Image: a chart]'), findsOneWidget);
  });

  testWidgets('an http link calls onOpenLink, a relative one does not', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      themed(
        AppMarkdown(
          'See [the site](https://x.example.test/page) and '
          '[the issue](/ABC/issues/ABC-1).',
          onOpenLink: opened.add,
        ),
      ),
    );

    await tester.tapOnText(find.textRange.ofSubstring('the site'));
    expect(opened, [Uri.parse('https://x.example.test/page')]);

    await tester.tapOnText(find.textRange.ofSubstring('the issue'));
    expect(opened, hasLength(1));
  });

  testWidgets('long content fits 360 pt at XXL text without overflow', (
    tester,
  ) async {
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
              child: AppMarkdown(
                '## A long heading that wraps at large text sizes\n\n'
                'A paragraph with a [link](https://x.example.test) and some '
                '**bold** words that wrap across several lines on a phone.\n\n'
                '- a list item that is long enough to wrap onto another line\n'
                '- a second item\n\n'
                '```\nsome code that is wider than the phone screen\n```',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
