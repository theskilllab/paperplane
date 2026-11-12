import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/data/auth_repository.dart';
import 'package:paperplane/features/connect/connect_error_copy.dart';
import 'package:paperplane/ui/ui.dart';

/// Asks for an existing `pcp_board_…` key, verifies it with one call, and
/// returns the session. Nothing is saved until the caller signs in.
Future<AuthSession?> showPasteTokenSheet(
  BuildContext context, {
  required Uri baseUrl,
}) => showAppSheet<AuthSession>(
  context: context,
  builder: (_) => _PasteTokenSheet(baseUrl: baseUrl),
);

class _PasteTokenSheet extends ConsumerStatefulWidget {
  const new({required this.baseUrl});

  final Uri baseUrl;

  @override
  ConsumerState<_PasteTokenSheet> createState() => _PasteTokenSheetState();
}

class _PasteTokenSheetState extends ConsumerState<_PasteTokenSheet> {
  final _controller = TextEditingController();
  ConnectError? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final token = _controller.text.trim();
    if (token.isEmpty) {
      setState(
        () => _error = const ConnectError(
          title: 'Paste a key',
          message: 'The key starts with pcp_board_.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(authRepositoryProvider)
          .verifyKey(baseUrl: widget.baseUrl, token: token);
      if (mounted) Navigator.of(context).pop(session);
    } on NoCompanyOnAccount {
      _show(
        const ConnectError(
          title: 'No company on this account',
          message: 'Ask the server admin to add this account to a company.',
        ),
      );
    } on ApiError catch (error) {
      _show(connectErrorFor(error, host: widget.baseUrl.host, pasting: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(ConnectError error) {
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AppSheet(
      title: 'Paste a board key',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create a board key in Paperclip, then paste it here. It is stored '
            'in the system secure storage.',
            style: context.pp.text.small.copyWith(color: context.pp.ink2),
          ),
          const SizedBox(height: Space.s4),
          AppTextField(
            label: 'Board key',
            controller: _controller,
            enabled: !_busy,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _verify(),
          ),
          if (error != null) ...[
            const SizedBox(height: Space.s3),
            AppBanner(
              kind: AppBannerKind.error,
              title: error.title,
              message: error.message,
            ),
          ],
          const SizedBox(height: Space.s4),
          AppButton(
            label: 'Verify and sign in',
            loadingLabel: 'Verifying',
            block: true,
            loading: _busy,
            onPressed: _busy ? null : _verify,
          ),
          const SizedBox(height: Space.s2),
          AppButton(
            label: 'Cancel',
            style: AppButtonStyle.secondary,
            block: true,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
