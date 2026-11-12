import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/features/account/disconnect_sheet.dart';
import 'package:paperplane/features/inbox/company_providers.dart';
import 'package:paperplane/ui/ui.dart';

/// What the switcher sheet can ask its caller to do after it closes.
enum _SwitcherAction { signOut }

/// Opens S3, the company switcher.
///
/// Picking a company stores it as last used and the Inbox reloads for it.
/// "Sign out" closes the sheet and asks "Disconnect this server?".
Future<void> showCompanySwitcher(BuildContext context) async {
  final action = await showAppSheet<_SwitcherAction>(
    context: context,
    builder: (_) => const _CompanySwitcherSheet(),
  );
  if (action == _SwitcherAction.signOut && context.mounted) {
    await showDisconnectSheet(context);
  }
}

class _CompanySwitcherSheet extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_CompanySwitcherSheet> createState() =>
      _CompanySwitcherSheetState();
}

class _CompanySwitcherSheetState extends ConsumerState<_CompanySwitcherSheet> {
  @override
  void initState() {
    super.initState();
    // Refresh the list on open. The cached one stays on screen meanwhile and
    // after a failure (S3 AC4).
    unawaited(
      Future.microtask(() {
        if (mounted) ref.invalidate(companiesProvider);
      }),
    );
  }

  void _pick(Company company) {
    // Let the sheet close first; the write to preferences is not awaited.
    Navigator.of(context).pop();
    unawaited(ref.read(activeCompanyIdProvider.notifier).select(company.id));
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider);
    final activeId = ref.watch(activeCompanyProvider)?.id;

    return AppSheet(
      title: 'Switch company',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (companies.hasValue) ...[
            if (companies.hasError) ...[
              const AppBanner(
                kind: AppBannerKind.offline,
                title: "Can't refresh the list",
                message: 'Showing the companies from the last time.',
              ),
              const SizedBox(height: Space.s3),
            ],
            AppCardList(
              children: [
                for (final company in companies.requireValue)
                  AppListRow(
                    key: ValueKey(company.id),
                    title: company.name,
                    meta: company.issuePrefix == null
                        ? null
                        : Text(company.issuePrefix!),
                    leading: const AppIcon(AppIconName.folder),
                    trailing: company.id == activeId
                        ? const AppIcon(AppIconName.check, size: 20)
                        : null,
                    semanticLabel: company.id == activeId
                        ? '${company.name}, current company'
                        : 'Switch to ${company.name}',
                    onTap: () => _pick(company),
                  ),
              ],
            ),
          ] else if (companies.hasError)
            AppEmptyState.error(
              title: "Can't load companies",
              message: 'Check your connection, then try again.',
              onAction: () => ref.invalidate(companiesProvider),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.s5),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: Space.s4),
          AppButton(
            label: 'Sign out',
            style: AppButtonStyle.secondary,
            block: true,
            onPressed: () => Navigator.of(context).pop(_SwitcherAction.signOut),
          ),
        ],
      ),
    );
  }
}
