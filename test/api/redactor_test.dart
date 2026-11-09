import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/redactor.dart';

void main() {
  // Built at runtime so the source never holds something that looks like a
  // real key.
  final key = ['pcp', 'board', 'fake0123456789abcdef'].join('_');

  test('masks board keys anywhere in text', () {
    final out = Redactor.redact('token=$key and again $key.');
    expect(out, isNot(contains('fake0123')));
    expect(out, contains(Redactor.mask));
  });

  test('masks bearer values even without the key prefix', () {
    final out = Redactor.redact('Authorization: Bearer abc.def-123');
    expect(out, isNot(contains('abc.def-123')));
    expect(out, contains('Bearer ${Redactor.mask}'));
  });

  test('masks credential headers by name and key patterns in others', () {
    final headers = Redactor.redactHeaders({
      'Authorization': 'Bearer $key',
      'authorization': 'x',
      'Cookie': 'session=abc',
      'Set-Cookie': 'session=abc',
      'X-Other': 'carries $key',
      'Accept': 'application/json',
    });
    expect(headers['Authorization'], Redactor.mask);
    expect(headers['authorization'], Redactor.mask);
    expect(headers['Cookie'], Redactor.mask);
    expect(headers['Set-Cookie'], Redactor.mask);
    expect(headers['X-Other'], isNot(contains('fake0123')));
    expect(headers['Accept'], 'application/json');
  });

  test('leaves harmless text alone', () {
    expect(Redactor.redact('GET /companies -> 200'), 'GET /companies -> 200');
  });
}
