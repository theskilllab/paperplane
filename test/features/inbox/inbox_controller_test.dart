import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/data/fake/demo_data.dart';
import 'package:paperplane/data/fake/fake_repositories.dart';
import 'package:paperplane/features/inbox/inbox_controller.dart';

void main() {
  test('removeItem drops one row and keeps the counts in step', () async {
    final now = DateTime.utc(2026, 11, 9, 12);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appEnvProvider.overrideWith(() => AppEnvController(const AppEnv())),
        inboxRepositoryProvider.overrideWithValue(
          FakeInboxRepository(now: () => now),
        ),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);

    final sub = container.listen(
      inboxProvider(demoCompanyId),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    final before = await container.read(inboxProvider(demoCompanyId).future);
    final first = before.feed.items.first;

    container.read(inboxProvider(demoCompanyId).notifier).removeItem(first.id);

    final after = container.read(inboxProvider(demoCompanyId)).value!;
    expect(after.feed.items.where((item) => item.id == first.id), isEmpty);
    expect(after.feed.totalCount, before.feed.totalCount - 1);
    final kind = first.sourceKind.wire;
    expect(
      after.feed.countsBySourceKind[kind],
      (before.feed.countsBySourceKind[kind] ?? 1) - 1,
    );
  });

  test('removeItem ignores an unknown id', () async {
    final now = DateTime.utc(2026, 11, 9, 12);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appEnvProvider.overrideWith(() => AppEnvController(const AppEnv())),
        inboxRepositoryProvider.overrideWithValue(
          FakeInboxRepository(now: () => now),
        ),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(
      inboxProvider(demoCompanyId),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    final before = await container.read(inboxProvider(demoCompanyId).future);

    container.read(inboxProvider(demoCompanyId).notifier).removeItem('nope');

    final after = container.read(inboxProvider(demoCompanyId)).value!;
    expect(after.feed.items, hasLength(before.feed.items.length));
  });
}
