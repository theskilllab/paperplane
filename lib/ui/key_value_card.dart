import 'package:flutter/material.dart';
import 'package:paperplane/ui/app_card.dart';
import 'package:paperplane/ui/theme/app_icons.dart';
import 'package:paperplane/ui/theme/tokens.dart';

/// One row of an [AppKeyValueCard].
@immutable
class AppKeyValue {
  /// Creates a row.
  const new(this.label, this.value, {this.icon});

  /// Left column, for example "Role".
  final String label;

  /// Right column, already formatted for reading.
  final String value;

  /// Optional 14 px icon before the value.
  final AppIconName? icon;
}

/// A card of label/value rows (design spec §2, `PpKeyValueCard`).
///
/// Labels are 14 ink3 on the left; values are 14/550, right-aligned. Long
/// values wrap instead of clipping, and each row reads as one spoken line.
class AppKeyValueCard extends StatelessWidget {
  /// Creates the card.
  const new({required this.rows, super.key});

  /// Rows in display order.
  final List<AppKeyValue> rows;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return AppCard(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Semantics(
              label: '${rows[i].label}: ${rows[i].value}',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(rows[i].label, style: pp.text.small),
                  ),
                  const SizedBox(width: Space.s3),
                  Flexible(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (rows[i].icon case final icon?) ...[
                          AppIcon(icon, size: 14, color: pp.ink2),
                          const SizedBox(width: Space.s1),
                        ],
                        Flexible(
                          child: Text(
                            rows[i].value,
                            textAlign: TextAlign.end,
                            style: pp.text.smallStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
