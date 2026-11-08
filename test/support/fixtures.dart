import 'dart:convert';
import 'dart:io';

/// Reads and decodes `test/fixtures/[name]`. `flutter test` runs from the
/// package root, so the relative path is stable.
Object? loadFixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// [loadFixture] as a JSON object.
Map<String, Object?> loadFixtureMap(String name) =>
    (loadFixture(name)! as Map).cast<String, Object?>();
