import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';

import 'issue_harness.dart';

/// Renders the S6 screenshots with the real Inter font, like
/// `test/screenshots_test.dart`: drawn by Flutter's test renderer, not taken on
/// a device. Always renders (a broken screen fails CI); writes the files only
/// with `PAPERPLANE_SCREENSHOTS=1`.
const _shotsDir = 'docs/screenshots';

const _phone = Size(390, 844);
const _tablet = Size(820, 1180);

Future<void> _loadInter() async {
  final bytes = File('assets/fonts/InterVariable.ttf').readAsBytesSync();
  final loader = FontLoader('Inter')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  final write = Platform.environment['PAPERPLANE_SCREENSHOTS'] == '1';
  final boundary = GlobalKey();

  setUpAll(_loadInter);

  Widget bounded(Widget app) => RepaintBoundary(key: boundary, child: app);

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    final png = await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(png.length, greaterThan(10000));
    if (write) {
      Directory(_shotsDir).createSync(recursive: true);
      File('$_shotsDir/$name.png').writeAsBytesSync(png);
    }
  }

  Future<void> top(WidgetTester tester) async {
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SingleChildScrollView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
  }

  for (final (label, size) in [('phone', _phone), ('tablet', _tablet)]) {
    testWidgets('S6 thread opened at the latest comment, $label', (
      tester,
    ) async {
      await pumpIssue(tester, size: size, wrapApp: bounded);
      await shoot(tester, 's6-thread-$label');
    });
  }

  testWidgets('S6 header and description, phone', (tester) async {
    await pumpIssue(tester, wrapApp: bounded);
    await top(tester);
    await shoot(tester, 's6-header-phone');
  });

  testWidgets('S6 "Not sent — Retry", phone', (tester) async {
    final h = await pumpIssue(tester, wrapApp: bounded);
    h.issues.failNextPost = const Offline();
    await tester.enterText(find.byType(EditableText), 'Ship it, thanks.');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send reply'));
    await tester.pumpAndSettle();
    await shoot(tester, 's6-not-sent-phone');
  });

  testWidgets('S6 @agent sheet, phone', (tester) async {
    await pumpIssue(tester, wrapApp: bounded);
    await tester.tap(find.bySemanticsLabel('Mention an agent'));
    await tester.pumpAndSettle();
    await shoot(tester, 's6-mention-sheet-phone');
  });
}
