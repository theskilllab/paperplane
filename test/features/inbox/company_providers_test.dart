import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/data/company_repository.dart';
import 'package:paperplane/features/inbox/company_providers.dart';

/// A repository whose answers a test releases when it wants.
class GatedCompanies implements CompanyRepository {
  /// Creates the fake with [cached] as the cold-start list.
  new(this.cached);

  /// The list a cold start would find, or null.
  final List<Company>? cached;

  /// One completer per `listCompanies` call, in call order.
  final calls = <Completer<List<Company>>>[];

  @override
  Future<List<Company>> listCompanies() {
    final call = Completer<List<Company>>();
    calls.add(call);
    return call.future;
  }

  @override
  List<Company>? cachedCompanies() => cached;
}

void main() {
  const cached = Company(id: 'old', name: 'Cached');
  const fresh = Company(id: 'fresh', name: 'Fresh');
  const stale = Company(id: 'stale', name: 'Stale');

  test('a late revalidation does not overwrite a newer build', () async {
    final repository = GatedCompanies([cached]);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [companyRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    // Cold start: the cached list, then one revalidation in flight.
    expect(await container.read(companiesProvider.future), [cached]);
    await pumpEventQueue();
    expect(repository.calls, hasLength(1));

    // Pull-to-refresh rebuilds while the first revalidation still runs.
    container.invalidate(companiesProvider);
    final newer = container.read(companiesProvider.future);
    await pumpEventQueue();
    expect(repository.calls, hasLength(2));

    repository.calls[1].complete([fresh]);
    expect(await newer, [fresh]);

    // The old answer arrives last and must be ignored.
    repository.calls[0].complete([stale]);
    await pumpEventQueue();

    expect(container.read(companiesProvider).value, [fresh]);
  });
}
