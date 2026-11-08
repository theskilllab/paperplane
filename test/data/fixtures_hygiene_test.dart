import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fixtures and demo data end up in a public repository. They must hold
/// nothing real: no key, no real host, no real person.
void main() {
  final files = [
    ...Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json')),
    File('lib/data/fake/demo_data.dart'),
  ];

  test('there are fixtures to check', () {
    expect(files.where((f) => f.path.endsWith('.json')), isNotEmpty);
  });

  for (final file in files) {
    group(file.path, () {
      final text = file.readAsStringSync();

      test('has no board key or bearer token', () {
        expect(text, isNot(contains('pcp_board_')));
        expect(text.toLowerCase(), isNot(contains('bearer ')));
        expect(text.toLowerCase(), isNot(contains('authorization')));
        expect(text.toLowerCase(), isNot(contains('password')));
        expect(text.toLowerCase(), isNot(contains('cookie')));
      });

      test('uses only reserved or example hostnames', () {
        final hosts = RegExp(r'https?://([A-Za-z0-9.\-]+)').allMatches(text);
        for (final m in hosts) {
          final host = m.group(1)!.toLowerCase();
          expect(
            host.endsWith('.invalid') ||
                host.endsWith('.example') ||
                host.endsWith('.test') ||
                host == 'example.com' ||
                host.endsWith('.example.com'),
            isTrue,
            reason: 'real-looking host "$host" in ${file.path}',
          );
        }
      });

      test('uses only example email domains', () {
        final emails = RegExp(r'[\w.+\-]+@([\w.\-]+)').allMatches(text);
        for (final m in emails) {
          final domain = m.group(1)!.toLowerCase();
          expect(
            domain.endsWith('.invalid') || domain.endsWith('example.com'),
            isTrue,
            reason: 'real-looking email domain "$domain" in ${file.path}',
          );
        }
      });

      test('has no IP addresses', () {
        expect(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b').hasMatch(text), isFalse);
      });
    });
  }
}
