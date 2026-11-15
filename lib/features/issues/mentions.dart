import 'package:flutter/services.dart';

/// Inserts `@[name] ` at the caret of [value] and puts the caret after it.
///
/// A selection is replaced. A space is added before the mention when the text
/// before it does not end in whitespace, so "hi" becomes "hi @Name ". Without
/// a valid caret the mention goes at the end.
TextEditingValue insertMention(TextEditingValue value, String name) {
  final text = value.text;
  final sel = value.selection;
  final start = sel.isValid ? sel.start.clamp(0, text.length) : text.length;
  final end = sel.isValid ? sel.end.clamp(0, text.length) : text.length;
  final before = text.substring(0, start);
  final after = text.substring(end);
  final needsSpace = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before);
  final mention = '${needsSpace ? ' ' : ''}@$name ';
  // Avoid "@Name  more" when the text after already starts with a space.
  final tail = after.startsWith(' ') ? after.substring(1) : after;
  final inserted = '$before$mention';
  return TextEditingValue(
    text: '$inserted$tail',
    selection: TextSelection.collapsed(offset: inserted.length),
  );
}

/// The body to send for [text].
///
/// Trims the text, then turns each `@Name` of an agent picked from the sheet
/// ([mentions] maps display name to agent id) into the Markdown link Paperclip
/// uses for agent mentions, `[@Name](agent://<id>)`. A name typed by hand that
/// was not picked stays plain text. The result is computed once per send and
/// stored, so a retry sends exactly the same string.
String buildCommentBody(String text, Map<String, String> mentions) {
  final trimmed = text.trim();
  if (mentions.isEmpty) return trimmed;
  final names = mentions.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(
    '(?<![\\w\\[])@(${names.map(RegExp.escape).join('|')})(?![\\w])',
  );
  return trimmed.replaceAllMapped(pattern, (m) {
    final name = m.group(1)!;
    return '[@$name](agent://${mentions[name]})';
  });
}
