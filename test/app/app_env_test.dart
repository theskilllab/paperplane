import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/app/app_env.dart';

void main() {
  test('demo is off by default, with and without the build define', () {
    expect(const AppEnv().demo, isFalse);
    // Tests run without --dart-define=PAPERPLANE_DEMO=true.
    expect(const AppEnv.fromEnvironment().demo, isFalse);
  });
}
