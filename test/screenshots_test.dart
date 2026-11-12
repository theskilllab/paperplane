import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/data/fake/demo_data.dart';

import 'features/inbox/inbox_harness.dart';

/// Renders the README screenshots: the demo app drawn by Flutter's test
/// renderer with the real Inter font. They are labelled "rendered" because no
/// iOS simulator or device took them.
///
/// This test always renders and checks that a picture comes out, so a broken
/// screen fails CI. It writes the files only when asked:
///
/// ```sh
/// PAPERPLANE_SCREENSHOTS=1 flutter test test/screenshots_test.dart
/// ```
///
/// They are not compared pixel by pixel. Text drawn with a real font differs
/// slightly between CPU architectures, which would make CI flaky. Review the
/// new images in the diff after you change a screen.
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

  Future<void> shoot(WidgetTester tester, String name) async {
    // Let flutter_svg finish parsing before the picture is taken.
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
    // PNG signature: something real was drawn.
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(png.length, greaterThan(10000));
    if (write) {
      Directory(_shotsDir).createSync(recursive: true);
      File('$_shotsDir/$name.png').writeAsBytesSync(png);
    }
  }

  Widget bounded(Widget app) => RepaintBoundary(key: boundary, child: app);

  for (final (label, size) in [('phone', _phone), ('tablet', _tablet)]) {
    testWidgets('S2 Inbox, populated, $label', (tester) async {
      await pumpInbox(tester, demo: true, size: size, wrapApp: bounded);
      await shoot(tester, 's2-inbox-$label');
    });

    testWidgets('S2 Inbox, empty, $label', (tester) async {
      final inbox = TrackingInbox()
        ..feed = AttentionFeedFromJson.empty(testNow);
      await pumpInbox(
        tester,
        demo: true,
        size: size,
        inbox: inbox,
        wrapApp: bounded,
      );
      await shoot(tester, 's2-inbox-empty-$label');
    });

    testWidgets('S3 company switcher, $label', (tester) async {
      await pumpInbox(tester, demo: true, size: size, wrapApp: bounded);
      await tester.tap(find.text('Acme Demo'));
      await tester.pumpAndSettle();
      await shoot(tester, 's3-switcher-$label');
    });
  }
}

/// Feeds for the screenshots.
abstract final class AttentionFeedFromJson {
  /// A feed with nothing in it.
  static AttentionFeed empty(DateTime now) =>
      AttentionFeed.fromJson(demoEmptyAttentionJson(now));
}
