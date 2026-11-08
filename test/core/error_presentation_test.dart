import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/core/error_presentation.dart';

void main() {
  const host = 'paperclip.example.test';

  test('offline and timeout say "Can\'t reach {host}" with Retry (G2)', () {
    for (final error in [const Offline(), const TimedOut()]) {
      final p = presentationFor(error, host: host);
      expect(p.kind, ErrorKind.offline);
      expect(p.title, "Can't reach $host");
      expect(p.retryable, isTrue);
    }
  });

  test('without a host the copy still reads well', () {
    expect(presentationFor(const Offline()).title, "Can't reach the server");
    expect(
      presentationFor(const Offline(), host: '').title,
      "Can't reach the server",
    );
  });

  test('401 asks to sign in again, with no retry (G3)', () {
    final p = presentationFor(const Unauthorized());
    expect(p.kind, ErrorKind.sessionExpired);
    expect(p.title, 'Your session expired');
    expect(p.message, 'Sign in again.');
    expect(p.retryable, isFalse);
  });

  test('403 on a read hides the server text (G4)', () {
    final p = presentationFor(const Forbidden('internal detail'));
    expect(p.kind, ErrorKind.noAccess);
    expect(p.title, "You don't have access to this");
    expect('${p.title} ${p.message}', isNot(contains('internal detail')));
    expect(p.retryable, isFalse);
  });

  test('403 on a write shows the server message when there is one (G4)', () {
    final p = presentationFor(
      const Forbidden('Only the board can do this'),
      forWrite: true,
    );
    expect(p.message, 'Only the board can do this');
    final empty = presentationFor(const Forbidden(''), forWrite: true);
    expect(empty.message, isNotEmpty);
  });

  test('AlreadyHandled reads "Already handled" (G10)', () {
    final p = presentationFor(const AlreadyHandled(409));
    expect(p.kind, ErrorKind.alreadyHandled);
    expect(p.title, 'Already handled');
  });

  test('5xx shows the status code and Retry, no stack (G5)', () {
    final p = presentationFor(const Server(502));
    expect(p.kind, ErrorKind.server);
    expect(p.title, 'Something went wrong');
    expect(p.detail, 'Error 502');
    expect(p.retryable, isTrue);
  });

  test('unexpected errors are generic and retryable', () {
    final p = presentationFor(const Unexpected('secret detail'));
    expect(p.kind, ErrorKind.server);
    expect('${p.title}${p.message}${p.detail}', isNot(contains('secret')));
  });

  test('HostNotAllowed explains the allow-list and does not retry', () {
    final p = presentationFor(const HostNotAllowed());
    expect(p.kind, ErrorKind.hostNotAllowed);
    expect(p.message, contains('allowed-hostname'));
    expect(p.retryable, isFalse);
  });

  test('TLS does not retry', () {
    expect(presentationFor(const Tls()).retryable, isFalse);
  });

  test('rate limit shows the wait', () {
    expect(
      presentationFor(const RateLimited(Duration(seconds: 12))).message,
      contains('12 s'),
    );
    expect(
      presentationFor(const RateLimited(null)).message,
      isNot(contains(' s.')),
    );
  });

  test('NotFound does not retry', () {
    expect(presentationFor(const NotFound()).retryable, isFalse);
  });
}
