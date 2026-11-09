import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/core/submit_controller.dart';
import 'package:paperplane/ui/ui.dart';

/// Whether the server confirmed that the key is revoked.
enum KeyRevocation {
  /// The server revoked the key, or it was already invalid.
  revoked,

  /// The server could not be reached. The key is gone from this device but may
  /// stay active on the server until it expires.
  failed,

  /// Demo mode: there is no key.
  notApplicable,
}

/// The disconnect action: one at a time, with the usual submit states.
final NotifierProvider<
  SubmitController<KeyRevocation>,
  SubmitState<KeyRevocation>
>
disconnectProvider =
    NotifierProvider.autoDispose<
      SubmitController<KeyRevocation>,
      SubmitState<KeyRevocation>
    >(SubmitController<KeyRevocation>.new);

/// Asks "Disconnect this server?" and, on confirm, revokes the key on the
/// server, deletes it on this device and returns to S1 (PRD S1 AC10).
///
/// If the revoke call fails (offline), the key is still deleted locally and
/// the user is told it may stay active until it expires.
Future<void> showDisconnectSheet(BuildContext context) {
  // Not disposed here: the request can finish after the sheet's route has
  // completed but before the sheet widget is gone. It holds no resources.
  final locked = ValueNotifier<bool>(false);
  return showAppSheet<void>(
    context: context,
    locked: locked,
    builder: (_) => _DisconnectSheet(locked: locked),
  );
}

class _DisconnectSheet extends ConsumerStatefulWidget {
  const new({required this.locked});

  final ValueNotifier<bool> locked;

  @override
  ConsumerState<_DisconnectSheet> createState() => _DisconnectSheetState();
}

class _DisconnectSheetState extends ConsumerState<_DisconnectSheet> {
  late final bool _demo;
  late final String _host;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    _demo = session is SignedIn && session.isDemo;
    _host = session is SignedIn ? session.baseUrl.host : 'this server';
    // Back and scrim taps do nothing while the request runs. Updated from a
    // listener, not from build, so the sheet's guard can rebuild safely.
    ref.listenManual(
      disconnectProvider,
      (_, state) => widget.locked.value = state.isSubmitting,
    );
  }

  Future<KeyRevocation> _disconnect() async {
    final repository = ref.read(sessionRepositoryProvider);
    final session = ref.read(sessionControllerProvider.notifier);
    final env = ref.read(appEnvProvider.notifier);
    // The sheet and the Inbox are gone by the time the toast shows.
    final overlay = Navigator.of(context, rootNavigator: true).overlay;

    var outcome = KeyRevocation.notApplicable;
    if (!_demo) {
      outcome = KeyRevocation.revoked;
      try {
        await repository.revokeCurrentKey();
      } on Unauthorized {
        // The key was already invalid: nothing left to revoke.
      } on ApiError {
        outcome = KeyRevocation.failed;
      }
    }

    // Close the sheet before the router swaps the screen under it.
    if (mounted) Navigator.of(context).pop();
    if (_demo) {
      env.exitDemo();
    } else {
      await session.signOut();
    }
    if (outcome == KeyRevocation.failed && overlay != null && overlay.mounted) {
      showAppToast(
        overlay.context,
        overlay: overlay,
        kind: AppToastKind.error,
        message:
            'Signed out here. The server could not be reached, so the key '
            'may stay active until it expires.',
      );
    }
    return outcome;
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final state = ref.watch(disconnectProvider);
    final busy = state.isSubmitting;

    return AppSheet(
      title: _demo ? 'Leave the demo?' : 'Disconnect this server?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _demo
                ? 'You are looking at sample data. Nothing was sent anywhere.'
                : "You will be signed out of $_host. This device's key is "
                      'revoked on the server and deleted here. You can sign '
                      'in again at any time.',
            style: pp.text.small,
          ),
          const SizedBox(height: Space.s4),
          AppButton(
            label: _demo ? 'Leave demo' : 'Disconnect',
            loadingLabel: 'Disconnecting',
            style: AppButtonStyle.danger,
            block: true,
            loading: busy,
            onPressed: () => unawaited(
              ref.read(disconnectProvider.notifier).submit(_disconnect),
            ),
          ),
          const SizedBox(height: Space.s2),
          AppButton(
            label: 'Cancel',
            style: AppButtonStyle.secondary,
            block: true,
            onPressed: busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
