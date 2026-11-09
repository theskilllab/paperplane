import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/core/submit_controller.dart';

final NotifierProvider<SubmitController<int>, SubmitState<int>> _submit =
    NotifierProvider.autoDispose<SubmitController<int>, SubmitState<int>>(
      SubmitController<int>.new,
    );

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(retry: (_, _) => null)
      // Keep the autoDispose provider alive for the test.
      ..listen(_submit, (_, _) {});
  });
  tearDown(() => container.dispose());

  SubmitState<int> read() => container.read(_submit);
  SubmitController<int> controller() => container.read(_submit.notifier);

  test('starts idle', () {
    expect(read(), isA<SubmitIdle<int>>());
    expect(read().isSubmitting, isFalse);
  });

  test('success carries the value', () async {
    final ran = await controller().submit(() async => 42);
    expect(ran, isTrue);
    expect(read(), isA<SubmitSuccess<int>>());
    expect((read() as SubmitSuccess<int>).value, 42);
  });

  test('is in flight while the action runs', () async {
    final gate = Completer<int>();
    final future = controller().submit(() => gate.future);
    expect(read().isSubmitting, isTrue);
    gate.complete(1);
    await future;
    expect(read().isSubmitting, isFalse);
  });

  test('one tap, one request: a second submit is ignored (G6)', () async {
    final gate = Completer<int>();
    var runs = 0;
    final first = controller().submit(() {
      runs++;
      return gate.future;
    });
    final second = await controller().submit(() async {
      runs++;
      return 2;
    });
    expect(second, isFalse);
    expect(runs, 1);
    gate.complete(1);
    await first;
    expect(runs, 1);
    expect((read() as SubmitSuccess<int>).value, 1);
  });

  test('an ApiError becomes SubmitFailure and the user can retry', () async {
    await controller().submit(() async => throw const Offline());
    expect(read(), isA<SubmitFailure<int>>());
    expect((read() as SubmitFailure<int>).error, isA<Offline>());

    await controller().submit(() async => 7);
    expect((read() as SubmitSuccess<int>).value, 7);
  });

  test('AlreadyHandled re-fetches once and reports it (G10)', () async {
    var refreshes = 0;
    await controller().submit(
      () async => throw const AlreadyHandled(422),
      onAlreadyHandled: () async => refreshes++,
    );
    expect(refreshes, 1);
    expect(read(), isA<SubmitAlreadyHandled<int>>());
  });

  test('AlreadyHandled still reports when the re-fetch fails', () async {
    await controller().submit(
      () async => throw const AlreadyHandled(409),
      onAlreadyHandled: () async => throw const Offline(),
    );
    expect(read(), isA<SubmitAlreadyHandled<int>>());
  });

  test('other errors do not trigger the re-fetch', () async {
    var refreshes = 0;
    await controller().submit(
      () async => throw const Server(500),
      onAlreadyHandled: () async => refreshes++,
    );
    expect(refreshes, 0);
  });

  test('a bug is rethrown and does not leave the button stuck', () async {
    await expectLater(
      controller().submit(() async => throw StateError('bug')),
      throwsStateError,
    );
    expect(read().isSubmitting, isFalse);
    expect((read() as SubmitFailure<int>).error, isA<Unexpected>());
  });

  test('reset returns to idle but never interrupts a request', () async {
    await controller().submit(() async => throw const Offline());
    controller().reset();
    expect(read(), isA<SubmitIdle<int>>());

    final gate = Completer<int>();
    final future = controller().submit(() => gate.future);
    controller().reset();
    expect(read().isSubmitting, isTrue);
    gate.complete(1);
    await future;
  });

  test('a result after the provider is disposed is dropped quietly', () async {
    final local = ProviderContainer(retry: (_, _) => null);
    final sub = local.listen(_submit, (_, _) {});
    final gate = Completer<int>();
    final future = local.read(_submit.notifier).submit(() => gate.future);
    sub.close();
    local.dispose();
    gate.complete(1);
    await expectLater(future, completes);
  });
}
