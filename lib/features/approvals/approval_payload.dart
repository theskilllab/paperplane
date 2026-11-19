import 'package:flutter/material.dart';
import 'package:paperplane/api/models/approval.dart';
import 'package:paperplane/ui/ui.dart';

/// Generic renderer for an approval's free-form [Approval.payload].
///
/// Short scalar values become a key/value card. Long text and
/// `plan`/`description`/`reason`-like fields render as safe Markdown. Nested
/// configuration maps are not shown: the app cannot render those faithfully,
/// and the screen links to Paperclip instead. An unknown type shows only its
/// summary (PRD S4 AC8).
class ApprovalPayloadView extends StatelessWidget {
  /// Creates the view.
  const new({required this.approval, this.onOpenLink, super.key});

  /// The approval whose payload is shown.
  final Approval approval;

  /// Passed to [AppMarkdown] for http(s) links.
  final void Function(Uri uri)? onOpenLink;

  static const _markdownKeys = {
    'plan',
    'description',
    'reason',
    'capabilities',
    'body',
    'details',
    'note',
    'summary',
  };

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    if (!approval.hasKnownBody) {
      final summary = approval.summary;
      return Text(
        summary == null || summary.isEmpty
            ? 'No details were sent with this request.'
            : summary,
        style: pp.text.body,
      );
    }

    final sections = <Widget>[];
    final rows = <AppKeyValue>[];
    for (final entry in approval.payload.entries) {
      final key = entry.key;
      final value = entry.value;
      final label = _label(key);
      if (key == 'title' || key == 'name' && value == approval.title) continue;
      if (value is String) {
        if (value.trim().isEmpty) continue;
        if (_markdownKeys.contains(key) || value.contains('\n')) {
          sections.add(_section(context, label, value));
        } else {
          rows.add(AppKeyValue(label, value));
        }
      } else if (value is num) {
        rows.add(
          AppKeyValue(label, key.endsWith('Cents') ? _money(value) : '$value'),
        );
      } else if (value is bool) {
        rows.add(AppKeyValue(label, value ? 'Yes' : 'No'));
      } else if (value is List &&
          value.every(
            (item) => item is String || item is num || item is bool,
          )) {
        if (key == 'risks' && value.isNotEmpty) {
          sections.add(
            _section(context, label, value.map((risk) => '- $risk').join('\n')),
          );
        } else if (value.isNotEmpty) {
          rows.add(AppKeyValue(label, value.join(', ')));
        }
      }
    }

    final children = <Widget>[
      for (final section in sections) ...[
        section,
        const SizedBox(height: Space.s4),
      ],
      if (rows.isNotEmpty) AppKeyValueCard(rows: rows),
    ];
    if (children.isEmpty) {
      final summary = approval.summary;
      return Text(
        summary ?? 'No details were sent with this request.',
        style: pp.text.body,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _section(BuildContext context, String label, String text) {
    final pp = context.pp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: pp.text.sectionTitle),
        const SizedBox(height: Space.s1 + 2),
        AppMarkdown(text, onOpenLink: onOpenLink),
      ],
    );
  }

  static String _label(String key) {
    final spaced = key
        .replaceAll('_', ' ')
        .replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .trim();
    if (spaced.isEmpty) return key;
    final words = spaced.split(' ');
    return [
      words.first[0].toUpperCase() + words.first.substring(1).toLowerCase(),
      for (final word in words.skip(1)) word.toLowerCase(),
    ].join(' ');
  }

  static String _money(num cents) =>
      '\$${(cents.toDouble() / 100).toStringAsFixed(2)}';
}
