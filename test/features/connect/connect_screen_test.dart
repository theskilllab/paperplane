import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/app/app.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/app_prefs.dart';
import 'package:paperplane/auth/key_store.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/connect/connect_screen.dart';
import 'package:paperplane/features/inbox/inbox_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_adapter.dart';

class _Harness {
  new({required this.container, required this.keys, required this.adapter});

  final ProviderContainer container;
  final InMemoryKeyStore keys;
  final FakeAdapter adapter;
}

FakeAdapter _signInAdapter({
  int signInStatus = 200,
  Object? health,
  int healthStatus = 200,
  List<String> companies = const ['company-demo-1'],
}) => FakeAdapter((o) async {
  switch ('${o.method} ${o.path}') {
    case 'GET /health':
      return jsonBody(
        health ??
            {
              'status': 'ok',
              'deploymentMode': 'authenticated',
              'deploymentExposure': 'private',
            },
        status: healthStatus,
      );
    case 'POST /auth/sign-in/email':
      if (signInStatus != 200) return jsonBody(null, status: signInStatus);
      return jsonBody(
        <String, Object?>{},
        headers: {
          'set-cookie': ['session=test; Path=/; HttpOnly'],
        },
      );
    case 'POST /board-api-keys':
      return jsonBody({
        'id': 'key-test',
        'name': 'Paperplane (Test Phone)',
        'token': 'test-board-key',
      }, status: 201);
    case 'GET /cli-auth/me':
      return jsonBody({...demoSessionJson, 'companyIds': companies});
    case 'POST /auth/sign-out':
      return jsonBody(<String, Object?>{});
    default:
      return jsonBody(null, status: 404);
  }
});

Future<_Harness> _pump(
  WidgetTester tester, {
  required FakeAdapter adapter,
  Map<String, Object> prefs = const {},
  List<Uri>? opened,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844) * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final keys = InMemoryKeyStore();
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appPrefsProvider.overrideWithValue(
        AppPrefs(await SharedPreferences.getInstance()),
      ),
      keyStoreProvider.overrideWithValue(keys),
      appEnvProvider.overrideWith(() => AppEnvController(const AppEnv())),
      httpAdapterProvider.overrideWithValue(adapter),
      deviceNameProvider.overrideWithValue('Test Phone'),
      companyRepositoryProvider.overrideWithValue(FakeCompanyRepository()),
      inboxRepositoryProvider.overrideWithValue(FakeInboxRepository()),
      sessionRepositoryProvider.overrideWithValue(FakeSessionRepository()),
      if (opened != null)
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PaperplaneApp(),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container: container, keys: keys, adapter: adapter);
}

Future<void> _fillForm(
  WidgetTester tester, {
  String url = 'paperclip.example.test',
  String email = 'person@example.test',
  String password = 'correct horse',
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), url);
  await tester.enterText(fields.at(1), email);
  await tester.enterText(fields.at(2), password);
}

Future<void> _tapVisible(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fresh install shows the form, fallbacks and the demo entry', (
    tester,
  ) async {
    await _pump(tester, adapter: _signInAdapter());

    expect(find.byType(ConnectScreen), findsOneWidget);
    expect(find.text('Connect to your Paperclip'), findsOneWidget);
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in with browser'), findsOneWidget);
    expect(find.text('Paste token'), findsOneWidget);
    expect(find.text('Explore the demo'), findsOneWidget);
  });

  testWidgets('signs in with https:// assumed and stores the minted key', (
    tester,
  ) async {
    final h = await _pump(tester, adapter: _signInAdapter());
    await _fillForm(tester);
    await _tapVisible(tester, 'Sign in');

    expect(find.byType(InboxScreen), findsOneWidget);
    expect(
      await h.keys.read('https://paperclip.example.test'),
      'test-board-key',
    );
    expect(
      h.adapter.requests.map((r) => '${r.method} ${r.path}'),
      containsAllInOrder([
        'GET /health',
        'POST /auth/sign-in/email',
        'POST /board-api-keys',
        'GET /cli-auth/me',
      ]),
    );
    final mint = h.adapter.requests.singleWhere(
      (r) => r.path == '/board-api-keys',
    );
    final body = mint.data! as Map;
    expect(body['name'], 'Paperplane (Test Phone)');
    expect(DateTime.parse(body['expiresAt'] as String).isUtc, isTrue);
    final signIn = h.adapter.requests.singleWhere(
      (r) => r.path == '/auth/sign-in/email',
    );
    expect(signIn.headers['Origin'], 'https://paperclip.example.test');
  });

  testWidgets('a wrong password keeps the form and clears the password', (
    tester,
  ) async {
    final h = await _pump(tester, adapter: _signInAdapter(signInStatus: 401));
    await _fillForm(tester);
    await _tapVisible(tester, 'Sign in');

    expect(find.byType(ConnectScreen), findsOneWidget);
    expect(find.text('Email or password is wrong'), findsOneWidget);
    final password = tester.widget<TextField>(find.byType(TextField).at(2));
    expect(password.controller!.text, isEmpty);
    expect(await h.keys.read('https://paperclip.example.test'), isNull);
  });

  testWidgets('a local_trusted instance is not supported', (tester) async {
    await _pump(
      tester,
      adapter: _signInAdapter(
        health: {'status': 'ok', 'deploymentMode': 'local_trusted'},
      ),
    );
    await _fillForm(tester);
    await _tapVisible(tester, 'Sign in');

    expect(find.text('This instance has no login'), findsOneWidget);
    expect(find.byType(ConnectScreen), findsOneWidget);
  });

  testWidgets('a host that the server does not allow explains who can fix it', (
    tester,
  ) async {
    await _pump(
      tester,
      adapter: _signInAdapter(
        healthStatus: 403,
        health: {
          'error': 'This hostname is not allowed for this Paperclip instance',
        },
      ),
    );
    await _fillForm(tester);
    await _tapVisible(tester, 'Sign in');

    expect(find.text('This address is not allowed'), findsOneWidget);
  });

  testWidgets('plain http to a public host is refused before any request', (
    tester,
  ) async {
    final h = await _pump(tester, adapter: _signInAdapter());
    await _fillForm(tester, url: 'http://paperclip.example.test');
    await _tapVisible(tester, 'Sign in');

    expect(
      find.textContaining('Plain http works only on your home network'),
      findsOneWidget,
    );
    expect(h.adapter.requests, isEmpty);
  });

  testWidgets('plain http to a private host shows the unencrypted banner', (
    tester,
  ) async {
    await _pump(tester, adapter: _signInAdapter());
    await tester.enterText(
      find.byType(TextField).first,
      'http://192.168.1.20:3100',
    );
    await tester.pump();

    expect(find.text('Not encrypted'), findsOneWidget);
  });

  testWidgets('paste token verifies before saving', (tester) async {
    final h = await _pump(
      tester,
      adapter: FakeAdapter((o) async {
        if (o.path == '/cli-auth/me') {
          expect(o.headers['Authorization'], 'Bearer pasted-board-key');
          return jsonBody(demoSessionJson);
        }
        return jsonBody(null, status: 404);
      }),
    );
    await tester.enterText(
      find.byType(TextField).first,
      'paperclip.example.test',
    );
    await _tapVisible(tester, 'Paste token');

    expect(find.text('Paste a board key'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'pasted-board-key');
    await _tapVisible(tester, 'Verify and sign in');

    expect(find.byType(InboxScreen), findsOneWidget);
    expect(
      await h.keys.read('https://paperclip.example.test'),
      'pasted-board-key',
    );
  });

  testWidgets('an account with no company gets a clear message', (
    tester,
  ) async {
    final h = await _pump(tester, adapter: _signInAdapter(companies: const []));
    await _fillForm(tester);
    await _tapVisible(tester, 'Sign in');

    expect(find.text('No company on this account'), findsOneWidget);
    expect(find.byType(ConnectScreen), findsOneWidget);
    expect(await h.keys.read('https://paperclip.example.test'), isNull);
    expect(
      h.adapter.requests.map((r) => r.path),
      contains('/cli-auth/revoke-current'),
    );
  });

  testWidgets('a pasted key that the server rejects saves nothing', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      adapter: FakeAdapter((o) async => jsonBody(null, status: 401)),
    );
    await tester.enterText(
      find.byType(TextField).first,
      'paperclip.example.test',
    );
    await _tapVisible(tester, 'Paste token');
    await tester.enterText(find.byType(TextField).last, 'bad-key');
    await _tapVisible(tester, 'Verify and sign in');

    expect(find.text('This key is not valid'), findsOneWidget);
    expect(await h.keys.read('https://paperclip.example.test'), isNull);
  });

  testWidgets('browser sign-in opens the approval page on the server host', (
    tester,
  ) async {
    final opened = <Uri>[];
    final adapter = FakeAdapter((o) async {
      return switch ('${o.method} ${o.path}') {
        'POST /cli-auth/challenges' => jsonBody({
          'id': 'challenge-1',
          'token': 'challenge-secret',
          'boardApiToken': 'test-board-key',
          'approvalPath': '/cli-auth/challenges/challenge-1',
          'pollPath': '/cli-auth/challenges/challenge-1',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          'suggestedPollIntervalMs': 1000,
        }, status: 201),
        'GET /cli-auth/challenges/challenge-1' => jsonBody({
          'status': 'pending',
        }),
        _ => jsonBody(<String, Object?>{}),
      };
    });
    await _pump(tester, adapter: adapter, opened: opened);
    await tester.enterText(
      find.byType(TextField).first,
      'paperclip.example.test',
    );
    await tester.ensureVisible(find.text('Sign in with browser').first);
    await tester.tap(find.text('Sign in with browser').first);
    // The waiting spinner animates forever, so pumpAndSettle would time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Waiting for approval'), findsOneWidget);
    expect(
      opened.single.toString(),
      'https://paperclip.example.test/cli-auth/challenges/challenge-1',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Waiting for approval'), findsNothing);
    expect(find.byType(ConnectScreen), findsOneWidget);
  });

  testWidgets('no connection shows a reachable message', (tester) async {
    await _pump(
      tester,
      adapter: FakeAdapter(
        (o) async => throw DioException.connectionError(
          requestOptions: o,
          reason: 'no route',
          error: const SocketException('no route'),
        ),
      ),
    );
    await _fillForm(tester);
    await _tapVisible(tester, 'Sign in');

    expect(find.text("Can't reach paperclip.example.test"), findsOneWidget);
  });
}
