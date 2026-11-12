import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/models/device_login.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/device_name.dart';
import 'package:paperplane/data/auth_repository.dart';
import 'package:paperplane/features/connect/connect_error_copy.dart';
import 'package:paperplane/ui/ui.dart';

/// Opens the system browser for Paperclip device login and polls until the
/// challenge is approved, denied or expired (THE-203 A2, the fallback flow).
Future<AuthSession?> showBrowserSignInSheet(
  BuildContext context, {
  required Uri baseUrl,
}) => showAppSheet<AuthSession>(
  context: context,
  builder: (_) => _BrowserSignInSheet(baseUrl: baseUrl),
);

class _BrowserSignInSheet extends ConsumerStatefulWidget {
  const new({required this.baseUrl});

  final Uri baseUrl;

  @override
  ConsumerState<_BrowserSignInSheet> createState() =>
      _BrowserSignInSheetState();
}

class _BrowserSignInSheetState extends ConsumerState<_BrowserSignInSheet> {
  late final AuthRepository _auth;
  late final Future<bool> Function(Uri) _openUrl;
  DeviceChallenge? _challenge;
  Timer? _timer;
  ConnectError? _error;
  bool _starting = true;
  bool _polling = false;
  bool _finished = false;
  DateTime? _nextPoll;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(authRepositoryProvider);
    _openUrl = ref.read(urlOpenerProvider);
    unawaited(_start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    final challenge = _challenge;
    if (challenge != null && !_finished) {
      unawaited(
        _auth.cancelDeviceLogin(baseUrl: widget.baseUrl, challenge: challenge),
      );
    }
    super.dispose();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _starting = true;
      _finished = false;
      _error = null;
    });
    try {
      final challenge = await _auth.startDeviceLogin(
        baseUrl: widget.baseUrl,
        clientName: keyNameForDevice(ref.read(deviceNameProvider)),
      );
      final approval = _auth.approvalUri(widget.baseUrl, challenge);
      if (approval == null) throw const Unexpected('no approval page');
      final opened = await _openUrl(approval);
      if (!mounted) return;
      if (!opened) {
        _fail(
          const ConnectError(
            title: 'Could not open the browser',
            message: 'Open the approval link on this device, then try again.',
          ),
        );
        return;
      }
      _challenge = challenge;
      setState(() => _starting = false);
      _timer = Timer.periodic(
        challenge.pollInterval,
        (_) => unawaited(_poll()),
      );
      unawaited(_poll());
    } on NoCompanyOnAccount {
      _fail(
        const ConnectError(
          title: 'No company on this account',
          message: 'Ask the server admin to add this account to a company.',
        ),
      );
    } on ApiError catch (error) {
      _fail(connectErrorFor(error, host: widget.baseUrl.host));
    } on Object {
      _fail(
        const ConnectError(
          title: 'Could not start browser sign-in',
          message: 'Try again, or use the email and password form.',
        ),
      );
    }
  }

  Future<void> _poll() async {
    final challenge = _challenge;
    if (challenge == null || _polling || _finished) return;
    final next = _nextPoll;
    if (next != null && DateTime.now().isBefore(next)) return;
    _polling = true;
    try {
      final status = await _auth.pollDeviceLogin(
        baseUrl: widget.baseUrl,
        challenge: challenge,
      );
      if (!mounted || _finished) return;
      switch (status) {
        case DeviceLoginStatus.approved:
          _timer?.cancel();
          _finished = true;
          await _verifyApproved(challenge);
        case DeviceLoginStatus.denied:
          _fail(
            const ConnectError(
              title: 'Sign-in was denied',
              message: 'Nothing was saved. Try again when you are ready.',
            ),
          );
        case DeviceLoginStatus.expired:
          _fail(
            const ConnectError(
              title: 'The code expired',
              message: 'Start again to get a new approval request.',
            ),
          );
        case DeviceLoginStatus.pending || DeviceLoginStatus.unknown:
          _nextPoll = null;
      }
    } on RateLimited catch (error) {
      _nextPoll = DateTime.now().add(
        error.retryAfter ?? const Duration(seconds: 5),
      );
    } on ApiError catch (error) {
      _fail(connectErrorFor(error, host: widget.baseUrl.host));
    } finally {
      _polling = false;
    }
  }

  Future<void> _verifyApproved(DeviceChallenge challenge) async {
    try {
      final session = await _auth.verifyKey(
        baseUrl: widget.baseUrl,
        token: challenge.boardApiToken,
      );
      if (mounted) Navigator.of(context).pop(session);
    } on NoCompanyOnAccount {
      _fail(
        const ConnectError(
          title: 'No company on this account',
          message: 'Ask the server admin to add this account to a company.',
        ),
      );
    } on ApiError catch (error) {
      _fail(connectErrorFor(error, host: widget.baseUrl.host));
    }
  }

  void _fail(ConnectError error) {
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _starting = false;
      _finished = true;
      _error = error;
    });
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    final challenge = _challenge;
    if (challenge != null && !_finished) {
      unawaited(
        _auth.cancelDeviceLogin(baseUrl: widget.baseUrl, challenge: challenge),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final error = _error;
    return AppSheet(
      title: 'Sign in with browser',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            AppBanner(
              kind: AppBannerKind.error,
              title: error.title,
              message: error.message,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _starting
                          ? 'Starting…'
                          : 'Waiting for approval. Approve the request in '
                                'your browser, then come back here.',
                      style: pp.text.small.copyWith(color: pp.ink2),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: Space.s4),
          if (error != null) ...[
            AppButton(
              label: 'Try again',
              block: true,
              onPressed: () => unawaited(_start()),
            ),
            const SizedBox(height: Space.s2),
          ],
          AppButton(
            label: 'Cancel',
            style: AppButtonStyle.secondary,
            block: true,
            onPressed: () => unawaited(_cancel()),
          ),
        ],
      ),
    );
  }
}
