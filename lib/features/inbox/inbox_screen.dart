import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:paperplane/api/models/attention.dart';
import 'package:paperplane/api/models/company.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/app/route_observer.dart';
import 'package:paperplane/app/routes.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/features/account/disconnect_sheet.dart';
import 'package:paperplane/features/inbox/company_providers.dart';
import 'package:paperplane/features/inbox/company_switcher.dart';
import 'package:paperplane/features/inbox/inbox_controller.dart';
import 'package:paperplane/features/inbox/inbox_format.dart';
import 'package:paperplane/features/inbox/inbox_rows.dart';
import 'package:paperplane/ui/ui.dart';

/// How often S2 refreshes while it is visible and the app is in the
/// foreground (PRD S2 AC2).
const inboxPollInterval = Duration(seconds: 30);

/// S2: what is waiting on the user, grouped Approvals / Questions / Needs
/// attention.
///
/// Refreshes on open, on return to the foreground, on pull-to-refresh and
/// every [inboxPollInterval] while visible. Polling stops while the app is in
/// the background or another screen covers this one.
class InboxScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen>
    with WidgetsBindingObserver, RouteAware {
  final _scroll = ScrollController();
  Timer? _timer;
  PageRoute<void>? _route;
  bool _foreground = true;
  bool _covered = false;
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;
    _scroll.addListener(_onScroll);
    _updatePolling(refreshNow: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void> && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updatePolling(refreshNow: _foreground);
  }

  @override
  void didPushNext() {
    _covered = true;
    _updatePolling(refreshNow: false);
  }

  @override
  void didPopNext() {
    _covered = false;
    _updatePolling(refreshNow: true);
  }

  void _updatePolling({required bool refreshNow}) {
    if (_foreground && !_covered) {
      if (refreshNow) _poll();
      _timer ??= Timer.periodic(inboxPollInterval, (_) => _poll());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _poll() {
    final id = ref.read(activeCompanyProvider)?.id;
    if (id == null) return;
    unawaited(ref.read(inboxProvider(id).notifier).refresh(silent: true));
  }

  void _onScroll() {
    final scrolled = _scroll.hasClients && _scroll.offset > 24;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  Future<void> _pullToRefresh() async {
    final id = ref.read(activeCompanyProvider)?.id;
    ref.invalidate(companiesProvider);
    if (id != null) await ref.read(inboxProvider(id).notifier).refresh();
  }

  Future<void> _open(Uri url) async {
    final session = ref.read(sessionControllerProvider);
    if (session is SignedIn && session.isDemo) {
      showAppToast(
        context,
        message: 'Demo mode. With a real server this opens in your browser.',
      );
      return;
    }
    final opened = await ref.read(urlOpenerProvider)(url);
    if (!opened && mounted) {
      showAppToast(
        context,
        kind: AppToastKind.error,
        message: "Couldn't open the page in your browser.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider);
    final active = ref.watch(activeCompanyProvider);
    final session = ref.watch(sessionControllerProvider);
    final signedIn = session is SignedIn ? session : null;
    final inbox = active == null ? null : ref.watch(inboxProvider(active.id));
    final total = inbox?.value?.feed.totalCount;

    return Scaffold(
      backgroundColor: context.pp.bg,
      appBar: AppNavBar(
        largeTitle: 'Inbox',
        largeTitleBadge: total == null ? null : '$total',
        scrolled: _scrolled,
        leading: active == null
            ? null
            : _CompanyButton(
                company: active,
                switchable: (companies.value?.length ?? 0) > 1,
              ),
        actions: [
          AppIconButton(
            icon: AppIconName.plus,
            semanticLabel: 'New issue',
            onPressed: () => context.push(AppRoutes.newIssue),
          ),
        ],
      ),
      body: AppColumn(
        child: Column(
          children: [
            if (signedIn != null && signedIn.baseUrl.scheme == 'http')
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.s4,
                  Space.s2,
                  Space.s4,
                  Space.s2,
                ),
                child: AppBanner(
                  kind: AppBannerKind.warn,
                  title: 'Not encrypted',
                  message: 'Only use this on your home network or Tailscale.',
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _pullToRefresh,
                color: context.pp.accent,
                backgroundColor: context.pp.bg,
                child: _body(signedIn, companies, active, inbox),
              ),
            ),
            // Without a loaded list there is no footer row, so keep Sign out
            // reachable when the feed cannot load.
            if (inbox?.hasValue != true && signedIn != null)
              Padding(
                padding: const EdgeInsets.all(Space.s4),
                child: _AccountRow(session: signedIn),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    SignedIn? session,
    AsyncValue<List<Company>> companies,
    Company? active,
    AsyncValue<InboxData>? inbox,
  ) {
    final host = session?.baseUrl.host;
    if (active == null || inbox == null) {
      return AsyncStateView<List<Company>>(
        value: companies,
        host: host,
        onRetry: () => ref.invalidate(companiesProvider),
        isEmpty: (list) => list.isEmpty,
        empty: const AppEmptyState(
          title: 'No company',
          message: 'Your account has no company on this server.',
        ),
        builder: (context, _) => const SizedBox.shrink(),
      );
    }

    return AsyncStateView<InboxData>(
      value: inbox,
      host: host,
      lastUpdated: inbox.value?.fetchedAt,
      skeletonRows: 4,
      onRetry: () => ref.read(inboxProvider(active.id).notifier).refresh(),
      isEmpty: (data) => data.feed.items.isEmpty,
      empty: _EmptyInbox(
        lastUpdated: inbox.value?.fetchedAt,
        footer: session == null ? null : _AccountRow(session: session),
      ),
      builder: (context, data) => _FeedList(
        controller: _scroll,
        data: data,
        now: ref.read(clockProvider)(),
        baseUrl: session?.baseUrl,
        onOpen: _open,
        footer: session == null ? null : _AccountRow(session: session),
      ),
    );
  }
}

class _CompanyButton extends ConsumerWidget {
  const new({required this.company, required this.switchable});

  final Company company;
  final bool switchable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pp = context.pp;
    final name = Text(
      company.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: pp.text.smallStrong,
    );
    if (!switchable) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s2),
        child: name,
      );
    }
    return Semantics(
      button: true,
      label: '${company.name}, switch company',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showCompanySwitcher(context),
        borderRadius: BorderRadius.circular(Radii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.tap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: name),
                const SizedBox(width: Space.s1),
                RotatedBox(
                  quarterTurns: 1,
                  child: AppIcon(AppIconName.chev, size: 16, color: pp.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  const new({
    required this.controller,
    required this.data,
    required this.now,
    required this.baseUrl,
    required this.onOpen,
    this.footer,
  });

  final ScrollController controller;
  final InboxData data;
  final DateTime now;
  final Uri? baseUrl;
  final void Function(Uri url) onOpen;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final feed = data.feed;
    final pp = context.pp;
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Space.s5),
      children: [
        for (final group in InboxGroup.values)
          if (feed.inGroup(group).isNotEmpty) ...[
            AppGroupHeader(groupLabel(group), count: groupCount(feed, group)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: AppCardList(
                children: [
                  for (final item in feed.inGroup(group))
                    AttentionRow(
                      key: ValueKey(item.id),
                      item: item,
                      agentNames: data.agentNames,
                      now: now,
                      onOpen: _openerFor(item),
                    ),
                ],
              ),
            ),
          ],
        if (feed.isTruncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, 0),
            child: Text(
              'Showing first ${feed.items.length} of ${feed.totalCount}',
              textAlign: TextAlign.center,
              style: pp.text.small.copyWith(color: pp.ink3),
            ),
          ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s5, Space.s4, 0),
            child: footer,
          ),
      ],
    );
  }

  VoidCallback? _openerFor(AttentionItem item) {
    final base = baseUrl;
    if (base == null) return null;
    final url = webUrlFor(base, item.subject.href);
    return url == null ? null : () => onOpen(url);
  }
}

class _EmptyInbox extends StatelessWidget {
  const new({required this.lastUpdated, this.footer});

  final DateTime? lastUpdated;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            children: [
              Expanded(
                child: AppEmptyState(
                  title: 'Nothing needs you',
                  message: lastUpdated == null
                      ? 'New requests show up here.'
                      : 'Last updated ${formatClock(lastUpdated!)}. '
                            'New requests show up here.',
                ),
              ),
              if (footer != null)
                Padding(padding: const EdgeInsets.all(Space.s4), child: footer),
            ],
          ),
        ),
      ],
    );
  }
}

/// Server and Sign out, at the bottom of the Inbox (design spec D4).
class _AccountRow extends StatelessWidget {
  const new({required this.session});

  final SignedIn session;

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      child: Row(
        children: [
          AppIcon(AppIconName.server, size: 20, color: pp.ink2),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.s2,
              children: [
                Text(session.baseUrl.host, style: pp.text.smallStrong),
                if (session.isDemo) const AppPill('Demo'),
              ],
            ),
          ),
          const SizedBox(width: Space.s3),
          AppButton(
            label: 'Sign out',
            style: AppButtonStyle.secondary,
            small: true,
            onPressed: () => showDisconnectSheet(context),
          ),
        ],
      ),
    );
  }
}
