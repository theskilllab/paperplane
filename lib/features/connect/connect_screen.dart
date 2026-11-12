import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paperplane/api/api_error.dart';
import 'package:paperplane/api/base_url.dart';
import 'package:paperplane/api/models/health.dart';
import 'package:paperplane/app/app_env.dart';
import 'package:paperplane/app/providers.dart';
import 'package:paperplane/auth/device_name.dart';
import 'package:paperplane/auth/session_controller.dart';
import 'package:paperplane/auth/session_state.dart';
import 'package:paperplane/data/auth_repository.dart';
import 'package:paperplane/features/connect/browser_sign_in_sheet.dart';
import 'package:paperplane/features/connect/connect_error_copy.dart';
import 'package:paperplane/features/connect/paste_token_sheet.dart';
import 'package:paperplane/ui/ui.dart';

/// S1: connect to a Paperclip server and sign in.
///
/// Password-first (THE-203): check `/health`, sign in with a browser session
/// cookie, mint a 30-day board key, verify it, discard the cookie. "Sign in
/// with browser" and "Paste token" are the fallbacks. The demo entry is kept
/// so the public build is usable without a server.
class ConnectScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  BaseUrlOk? _parsed;
  String? _urlError;
  ConnectError? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    if (session is SignedOut) {
      final url = session.lastBaseUrl;
      if (url != null) {
        _url.text = url;
        final parsed = BaseUrl.parse(url);
        if (parsed is BaseUrlOk) _parsed = parsed;
      }
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _expired {
    final session = ref.read(sessionControllerProvider);
    return session is SignedOut && session.reason == SignedOutReason.expired;
  }

  void _urlChanged(String value) {
    final parsed = BaseUrl.parse(value);
    setState(() {
      _urlError = null;
      _parsed = parsed is BaseUrlOk ? parsed : null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();

    final urlText = _url.text.trim();
    final parsed = BaseUrl.parse(urlText);
    if (parsed is! BaseUrlOk) {
      setState(() {
        _parsed = null;
        _urlError = _urlProblem(parsed as BaseUrlRejected);
        _error = null;
      });
      return;
    }
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(
        () => _error = const ConnectError(
          title: 'Enter your email',
          message: 'Use the email of your Paperclip account.',
        ),
      );
      _emailFocus.requestFocus();
      return;
    }
    final password = _password.text;
    if (password.isEmpty) {
      setState(
        () => _error = const ConnectError(
          title: 'Enter your password',
          message: 'The password is used once and is never stored.',
        ),
      );
      _passwordFocus.requestFocus();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _urlError = null;
      _parsed = parsed;
    });

    final auth = ref.read(authRepositoryProvider);
    AuthSession? minted;
    try {
      final health = await auth.health(parsed.uri);
      if (!health.isHealthy) {
        _show(
          const ConnectError(
            title: 'This is not a Paperclip server',
            message:
                'The address answered, but not with a Paperclip health '
                'check. Check the address and the server version.',
          ),
        );
        return;
      }
      switch (health.mode) {
        case DeploymentMode.localTrusted:
          _show(
            const ConnectError(
              title: 'This instance has no login',
              message:
                  'It runs in local trusted mode, which Paperplane does '
                  'not support. Ask the server admin to enable accounts.',
            ),
          );
          return;
        case DeploymentMode.unknown:
          _show(
            const ConnectError(
              title: 'Unsupported server',
              message:
                  'This Paperclip version reports a login mode the app '
                  'does not know. Update Paperclip or the app.',
            ),
          );
          return;
        case DeploymentMode.authenticated:
          break;
      }

      final signedIn = await auth.signIn(
        baseUrl: parsed.uri,
        email: email,
        password: password,
        keyName: keyNameForDevice(ref.read(deviceNameProvider)),
      );
      minted = signedIn;
      await ref
          .read(sessionControllerProvider.notifier)
          .signIn(baseUrl: parsed.uri, token: signedIn.token);
    } on NoCompanyOnAccount {
      _show(
        const ConnectError(
          title: 'No company on this account',
          message: 'Ask the server admin to add this account to a company.',
        ),
      );
    } on ApiError catch (error) {
      if (error is Unauthorized) _password.clear();
      _show(connectErrorFor(error, host: parsed.uri.host));
    } on Object {
      final key = minted?.token;
      if (key != null) {
        // The key was minted but could not be saved on this device. Do not
        // leave it live on the server.
        unawaited(auth.revokeKey(baseUrl: parsed.uri, token: key));
        _show(
          const ConnectError(
            title: 'Could not save the key',
            message: 'The device secure storage refused the key. Try again.',
          ),
        );
      } else {
        _show(connectErrorFor(const Unexpected(), host: parsed.uri.host));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteToken() async {
    final url = _parsed;
    if (url == null) {
      setState(() => _urlError = 'Enter the server address first.');
      return;
    }
    final session = await showPasteTokenSheet(context, baseUrl: url.uri);
    if (session == null || !mounted) return;
    await ref
        .read(sessionControllerProvider.notifier)
        .signIn(baseUrl: url.uri, token: session.token);
  }

  Future<void> _browserSignIn() async {
    final url = _parsed;
    if (url == null) {
      setState(() => _urlError = 'Enter the server address first.');
      return;
    }
    final session = await showBrowserSignInSheet(context, baseUrl: url.uri);
    if (session == null || !mounted) return;
    await ref
        .read(sessionControllerProvider.notifier)
        .signIn(baseUrl: url.uri, token: session.token);
  }

  void _show(ConnectError error) {
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.pp;
    final error = _error;
    final unencrypted = _parsed != null && !_parsed!.encrypted;

    return Scaffold(
      backgroundColor: pp.bg,
      body: SafeArea(
        child: AppColumn(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              Space.s4,
              Space.s6,
              Space.s4,
              Space.s4 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: pp.ink,
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: const Center(
                        child: AppIcon(
                          AppIconName.plane,
                          size: 26,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  Semantics(
                    header: true,
                    child: Text(
                      'Connect to your Paperclip',
                      style: pp.text.largeTitle,
                    ),
                  ),
                  const SizedBox(height: Space.s2),
                  Text(
                    'Sign in to your self-hosted Paperclip server. Paperplane '
                    'is an unofficial client and talks only to the server you '
                    'choose.',
                    style: pp.text.small.copyWith(color: pp.ink2),
                  ),
                  const SizedBox(height: Space.s4),
                  if (_expired) ...[
                    const AppBanner(
                      kind: AppBannerKind.warn,
                      title: 'Your session expired',
                      message: 'Sign in again to continue.',
                    ),
                    const SizedBox(height: Space.s3),
                  ],
                  if (unencrypted) ...[
                    const AppBanner(
                      kind: AppBannerKind.warn,
                      title: 'Not encrypted',
                      message:
                          'Only use this on your home network or '
                          'Tailscale.',
                    ),
                    const SizedBox(height: Space.s3),
                  ],
                  AppTextField(
                    label: 'Server address',
                    controller: _url,
                    help: 'For example https://paperclip.example.com',
                    errorText: _urlError,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    onChanged: _urlChanged,
                    onSubmitted: (_) => _emailFocus.requestFocus(),
                  ),
                  const SizedBox(height: Space.s3),
                  AppTextField(
                    label: 'Email',
                    controller: _email,
                    focusNode: _emailFocus,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: Space.s3),
                  AppTextField(
                    label: 'Password',
                    controller: _password,
                    focusNode: _passwordFocus,
                    enabled: !_busy,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unawaited(_submit()),
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
                    label: 'Sign in',
                    loadingLabel: 'Signing in',
                    block: true,
                    loading: _busy,
                    onPressed: _busy ? null : () => unawaited(_submit()),
                  ),
                  const SizedBox(height: Space.s2),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: Space.s4,
                    children: [
                      AppButton(
                        label: 'Sign in with browser',
                        style: AppButtonStyle.ghost,
                        small: true,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_browserSignIn()),
                      ),
                      AppButton(
                        label: 'Paste token',
                        style: AppButtonStyle.ghost,
                        small: true,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_pasteToken()),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s5),
                  Text(
                    'Your board key is stored in the system secure storage. It '
                    'has your full power on this server.',
                    textAlign: TextAlign.center,
                    style: pp.text.micro.copyWith(color: pp.ink3),
                  ),
                  const SizedBox(height: Space.s2),
                  AppButton(
                    label: 'Explore the demo',
                    style: AppButtonStyle.secondary,
                    block: true,
                    onPressed: _busy
                        ? null
                        : ref.read(appEnvProvider.notifier).enterDemo,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _urlProblem(BaseUrlRejected rejected) => switch (rejected.problem) {
    BaseUrlProblem.empty => 'Include the server address.',
    BaseUrlProblem.invalid =>
      'Enter a full address, for example https://paperclip.example.com.',
    BaseUrlProblem.insecurePublicHost =>
      'Use https:// for a public address. Plain http works only on your home '
          'network or Tailscale.',
  };
}
