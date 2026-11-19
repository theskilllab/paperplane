import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/features/issues/mentions.dart';

TextEditingValue v(String text, [int? at]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: at ?? text.length),
);

void main() {
  group('insertMention', () {
    test('into an empty field', () {
      final out = insertMention(TextEditingValue.empty, 'Chief Example');
      expect(out.text, '@Chief Example ');
      expect(out.selection.baseOffset, out.text.length);
    });

    test('at the caret, in the middle', () {
      final out = insertMention(v('Hello  world', 6), 'Bo');
      expect(out.text, 'Hello @Bo world');
      expect(out.selection.baseOffset, 'Hello @Bo '.length);
    });

    test('adds a space after text that has none', () {
      expect(insertMention(v('Hi'), 'Bo').text, 'Hi @Bo ');
    });

    test('replaces a selection', () {
      final out = insertMention(
        const TextEditingValue(
          text: 'ask XXXX now',
          selection: TextSelection(baseOffset: 4, extentOffset: 8),
        ),
        'Bo',
      );
      expect(out.text, 'ask @Bo now');
    });

    test('without a caret it goes at the end', () {
      final out = insertMention(const TextEditingValue(text: 'Hi '), 'Bo');
      expect(out.text, 'Hi @Bo ');
    });

    test('a caret past the end is clamped', () {
      expect(insertMention(v('Hi', 99), 'Bo').text, 'Hi @Bo ');
    });
  });

  group('buildCommentBody', () {
    const mentions = {'Chief Example': 'agent-ceo', 'Chief': 'agent-short'};

    test('trims and keeps plain text', () {
      expect(buildCommentBody('  hello\n', const {}), 'hello');
      expect(buildCommentBody('   ', const {}), '');
    });

    test('turns a picked mention into the agent link', () {
      expect(
        buildCommentBody('Hi @Chief Example, ok?', mentions),
        'Hi [@Chief Example](agent://agent-ceo), ok?',
      );
    });

    test('the longest name wins over a prefix name', () {
      expect(
        buildCommentBody('@Chief Example and @Chief', mentions),
        '[@Chief Example](agent://agent-ceo) and [@Chief](agent://agent-short)',
      );
    });

    test('a name that was not picked stays plain text', () {
      expect(buildCommentBody('@Someone else', mentions), '@Someone else');
    });

    test('does not touch part of a longer word or an email', () {
      expect(
        buildCommentBody('mail me@Chief or @Chiefs', mentions),
        'mail me@Chief or @Chiefs',
      );
    });

    test('is deterministic, so a retry sends the same body', () {
      expect(
        buildCommentBody('@Chief Example hi', mentions),
        buildCommentBody('@Chief Example hi', mentions),
      );
    });
  });
}
