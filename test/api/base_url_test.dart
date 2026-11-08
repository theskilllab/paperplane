import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/base_url.dart';

BaseUrlOk ok(String input) {
  final result = BaseUrl.parse(input);
  expect(result, isA<BaseUrlOk>(), reason: input);
  return result as BaseUrlOk;
}

BaseUrlProblem problem(String input) {
  final result = BaseUrl.parse(input);
  expect(result, isA<BaseUrlRejected>(), reason: input);
  return (result as BaseUrlRejected).problem;
}

void main() {
  group('BaseUrl.parse', () {
    test('normalises case, query, fragment and trailing slashes', () {
      final url = ok('  HTTPS://Paperclip.Example.TEST:8443/base///?x=1#frag ');
      expect(url.uri.toString(), 'https://paperclip.example.test:8443/base');
      expect(url.encrypted, isTrue);
      expect(url.key, 'https://paperclip.example.test:8443/base');
    });

    test('rejects empty input', () {
      expect(problem('   '), BaseUrlProblem.empty);
    });

    test('rejects input without a scheme or host', () {
      expect(problem('paperclip.example.test'), BaseUrlProblem.invalid);
      expect(problem('https://'), BaseUrlProblem.invalid);
      expect(problem('not a url'), BaseUrlProblem.invalid);
    });

    test('rejects other schemes and embedded credentials', () {
      expect(problem('ftp://paperclip.example.test'), BaseUrlProblem.invalid);
      expect(
        problem('https://user:pass@paperclip.example.test'),
        BaseUrlProblem.invalid,
      );
    });

    test('rejects plain http to a public host', () {
      expect(
        problem('http://paperclip.example.test'),
        BaseUrlProblem.insecurePublicHost,
      );
      expect(problem('http://8.8.8.8'), BaseUrlProblem.insecurePublicHost);
      expect(problem('http://172.32.0.1'), BaseUrlProblem.insecurePublicHost);
    });

    test(
      'allows plain http to private and local hosts, flagged unencrypted',
      () {
        for (final host in [
          '10.1.2.3',
          '172.16.0.1',
          '172.31.255.255',
          '192.168.1.20',
          '100.64.0.1',
          '100.127.255.255',
          '127.0.0.1',
          'localhost',
          'nas',
          'printer.local',
          'box.tail1234.ts.net',
        ]) {
          final url = ok('http://$host:3100');
          expect(url.encrypted, isFalse, reason: host);
        }
      },
    );

    test('allows https to any host', () {
      expect(ok('https://8.8.8.8').encrypted, isTrue);
    });
  });

  group('BaseUrl.isPrivateHost', () {
    test('judges the host string only', () {
      expect(BaseUrl.isPrivateHost('100.63.255.255'), isFalse);
      expect(BaseUrl.isPrivateHost('100.128.0.1'), isFalse);
      expect(BaseUrl.isPrivateHost('192.169.0.1'), isFalse);
      expect(BaseUrl.isPrivateHost('my.nas.example.test'), isFalse);
      expect(BaseUrl.isPrivateHost('::1'), isTrue);
    });
  });
}
