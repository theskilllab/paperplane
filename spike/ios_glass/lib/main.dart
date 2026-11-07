// Throwaway THE-203 spike. It is not product code and must not be merged.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'paperclip_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  runApp(
    LiquidGlassWidgets.wrap(
      child: const SpikeApp(),
      brightnessResolver: _materialBrightness,
    ),
  );
}

Brightness? _materialBrightness(BuildContext context) {
  return Theme.maybeOf(context)?.brightness;
}

class SpikeApp extends StatefulWidget {
  const SpikeApp({super.key});

  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> {
  bool _forceSolid = false;
  bool _showPerformanceOverlay = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paperplane spike',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: _showPerformanceOverlay,
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) {
        return GlassAccessibilityScope(
          reduceTransparency: _forceSolid ? true : null,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: SpikeHome(
        forceSolid: _forceSolid,
        showPerformanceOverlay: _showPerformanceOverlay,
        onForceSolidChanged: (value) => setState(() => _forceSolid = value),
        onPerformanceOverlayChanged: (value) =>
            setState(() => _showPerformanceOverlay = value),
      ),
    );
  }
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({
    required this.forceSolid,
    required this.showPerformanceOverlay,
    required this.onForceSolidChanged,
    required this.onPerformanceOverlayChanged,
    super.key,
  });

  final bool forceSolid;
  final bool showPerformanceOverlay;
  final ValueChanged<bool> onForceSolidChanged;
  final ValueChanged<bool> onPerformanceOverlayChanged;

  @override
  State<SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<SpikeHome> {
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final List<String> _log = <String>[];

  int _tab = 0;
  bool _busy = false;

  Timer? _pollTimer;
  bool _pollInFlight = false;
  DateTime? _pollNotBefore;
  String? _lastPollStatus;
  PaperclipClient? _deviceClient;
  String? _devicePollPath;
  String? _deviceToken;
  String? _deviceBoardToken;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _deviceClient?.close();
    _baseUrl.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _redact(String value) {
    var text = value;
    final base = _baseUrl.text.trim();
    if (base.length >= 8) text = text.replaceAll(base, '<base-url>');
    final email = _email.text.trim();
    if (email.length >= 5) text = text.replaceAll(email, '<email>');
    final password = _password.text;
    if (password.length >= 6) text = text.replaceAll(password, '<password>');
    text = text.replaceAll(
      RegExp(r'pcp_board_[A-Za-z0-9]+'),
      'pcp_board_<redacted>',
    );
    text = text.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._-]+'),
      'Bearer <redacted>',
    );
    return text;
  }

  void _logLine(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$timestamp] ${_redact(message)}';
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  PaperclipClient? _clientFromForm() {
    final raw = _baseUrl.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      _logLine('Enter a base URL like http://192.168.1.10:3000');
      return null;
    }
    return PaperclipClient(baseUrl: raw);
  }

  Future<void> _checkHealth() async {
    final client = _clientFromForm();
    if (client == null) return;
    try {
      _logLine('GET /api/health (anonymous)');
      final response = await client.health();
      final data = response.json;
      _logLine(
        'GET /api/health -> ${response.status} '
        'status=${data?['status'] ?? '<none>'} '
        'version=${data?['version'] ?? '<none>'}',
      );
      if (response.status == 200) {
        _logLine(
          'If this is a LAN address, the iOS Local Network prompt should appear now.',
        );
      }
    } catch (error) {
      _logLine('Error: $error');
    } finally {
      client.close();
    }
  }

  Future<void> _runPasswordFirst() async {
    if (_busy) return;
    final client = _clientFromForm();
    if (client == null) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      client.close();
      _logLine('Enter the test account email and password.');
      return;
    }
    setState(() => _busy = true);
    _logLine('Password-first: sign-in');
    try {
      final signIn = await client.signIn(email: email, password: password);
      _logLine(
        'POST /api/auth/sign-in/email -> ${signIn.status}${_retryText(signIn)}',
      );
      if (signIn.status != 200) {
        _logLine('Sign-in failed: ${signIn.summary}');
        if (signIn.status == 429) {
          _logLine('Wait for the retry window before you try again.');
        }
        return;
      }

      final mint = await client.mintBoardKey(
        name: 'Paperplane iOS spike ${DateTime.now().toIso8601String()}',
      );
      final token = mint.json?['token'] as String?;
      _logLine(
        'POST /api/board-api-keys -> ${mint.status}${_retryText(mint)} '
        'key=${PaperclipClient.redactKey(token)}',
      );
      if (mint.status != 201 || token == null) {
        _logLine('Mint failed: ${mint.summary}');
        if (mint.status == 403) {
          _logLine(
            '403 is the Origin guard. Check PAPERCLIP_PUBLIC_URL or TRUST_PROXY.',
          );
        }
        return;
      }

      final me = await client.me(token);
      _logLine('GET /api/cli-auth/me -> ${me.status}');
      final health = await client.health(token: token);
      _logLine(
        'GET /api/health (auth) -> ${health.status} '
        'version=${health.json?['version'] ?? '<none>'}',
      );

      final signOut = await client.signOut();
      _logLine(
        'POST /api/auth/sign-out -> ${signOut.status}${_retryText(signOut)}',
      );
      final after = await client.health(token: token);
      _logLine(
        'GET /api/health (key after sign-out) -> ${after.status} '
        '(the board key stays valid by design)',
      );
    } catch (error) {
      _logLine('Error: $error');
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startDeviceLogin() async {
    if (_busy) return;
    final client = _clientFromForm();
    if (client == null) return;
    _pollTimer?.cancel();
    _deviceClient?.close();
    _deviceClient = client;
    _lastPollStatus = null;
    _pollNotBefore = null;
    setState(() => _busy = true);
    _logLine('Device login: create challenge');
    try {
      final challenge = await client.createChallenge();
      final data = challenge.json;
      _logLine(
        'POST /api/cli-auth/challenges -> ${challenge.status}'
        '${_retryText(challenge)}',
      );
      if (challenge.status != 201 || data == null) {
        _logLine('Challenge failed: ${challenge.summary}');
        return;
      }

      final boardToken = data['boardApiToken'] as String?;
      final token = data['token'] as String?;
      final pollPath = data['pollPath'] as String?;
      final approvalUrl = data['approvalUrl'] as String?;
      if (boardToken == null ||
          token == null ||
          pollPath == null ||
          approvalUrl == null) {
        _logLine('Challenge response is missing a field.');
        return;
      }

      _deviceBoardToken = boardToken;
      _deviceToken = token;
      _devicePollPath = pollPath;
      _logLine(
        'Challenge created. boardApiToken ${PaperclipClient.redactKey(boardToken)}',
      );
      _logLine('Opening the approval page in Safari. Sign in and approve.');
      final uri = Uri.tryParse(approvalUrl);
      if (uri == null) {
        _logLine('Approval URL is not valid.');
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      _logLine('Safari launch -> $opened');

      _pollTimer?.cancel();
      final timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _pollDevice(client),
      );
      setState(() => _pollTimer = timer);
      _pollDevice(client);
    } catch (error) {
      _logLine('Error: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pollDevice(PaperclipClient client) async {
    if (_pollInFlight) return;
    final notBefore = _pollNotBefore;
    if (notBefore != null && DateTime.now().isBefore(notBefore)) return;
    final pollPath = _devicePollPath;
    final token = _deviceToken;
    if (pollPath == null || token == null) return;
    _pollInFlight = true;
    try {
      final response = await client.pollDevice(
        pollPath: pollPath,
        token: token,
      );
      if (response.status == 429) {
        final seconds = response.retryAfter ?? 5;
        _pollNotBefore = DateTime.now().add(Duration(seconds: seconds));
        _logLine('Poll 429; wait ${seconds}s (Retry-After)');
        return;
      }
      if (response.status != 200) {
        _logLine('Poll -> ${response.status}: ${response.summary}');
        return;
      }
      final status = response.json?['status'] as String? ?? 'unknown';
      if (status != _lastPollStatus) {
        _lastPollStatus = status;
        _logLine('Poll -> $status');
      }
      if (status == 'approved') {
        _pollTimer?.cancel();
        _pollTimer = null;
        _devicePollPath = null;
        _deviceToken = null;
        final boardToken = _deviceBoardToken;
        _deviceBoardToken = null;
        if (boardToken == null) {
          _logLine('Approved but no boardApiToken is available.');
          return;
        }
        final me = await client.me(boardToken);
        _logLine('GET /api/cli-auth/me (device key) -> ${me.status}');
        final health = await client.health(token: boardToken);
        _logLine(
          'GET /api/health (device key) -> ${health.status} '
          'version=${health.json?['version'] ?? '<none>'}',
        );
        client.close();
        if (_deviceClient == client) _deviceClient = null;
      } else if (status == 'expired' ||
          status == 'cancelled' ||
          status == 'denied') {
        _pollTimer?.cancel();
        _pollTimer = null;
        _devicePollPath = null;
        _deviceToken = null;
        _deviceBoardToken = null;
        _logLine('Device challenge $status.');
      }
    } catch (error) {
      _logLine('Poll error: $error');
    } finally {
      _pollInFlight = false;
    }
  }

  void _stopDeviceLogin() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _devicePollPath = null;
    _deviceToken = null;
    _deviceBoardToken = null;
    _deviceClient?.close();
    _deviceClient = null;
    setState(() {});
    _logLine('Polling stopped.');
  }

  String _retryText(ApiResponse response) {
    final seconds = response.retryAfter;
    return seconds == null ? '' : ' retry-after=${seconds}s';
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log.reversed.join('\n')));
    _logLine('Copied ${_log.length} redacted lines to the clipboard.');
  }

  Future<void> _openSheet() async {
    await GlassSheet.show<void>(
      context: context,
      builder: (sheetContext) => Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Glass sheet',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'If this text is readable and the background is blurred, '
                'the sheet renders.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF07111F), Color(0xFF2A1458), Color(0xFF0B4F5C)],
          ),
        ),
      ),
      appBar: const GlassAppBar(title: Text('Paperplane spike')),
      bottomBar: GlassTabBar.bottom(
        tabs: const [
          GlassTab(icon: Icon(Icons.lock_outline), label: 'Auth'),
          GlassTab(icon: Icon(Icons.auto_awesome), label: 'Glass'),
          GlassTab(icon: Icon(Icons.checklist), label: 'Checks'),
        ],
        selectedIndex: _tab,
        onTabSelected: (index) => setState(() => _tab = index),
      ),
      body: Material(type: MaterialType.transparency, child: _tabBody()),
    );
  }

  Widget _tabBody() {
    switch (_tab) {
      case 1:
        return _glassTab();
      case 2:
        return const _ChecksTab();
      default:
        return _authTab();
    }
  }

  Widget _authTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        GlassContainer.card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Connection',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'The app keeps the password and board key in memory only.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              GlassTextField(
                controller: _baseUrl,
                placeholder: 'Base URL (http://192.168.1.10:3000)',
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              GlassTextField(
                controller: _email,
                placeholder: 'Test account email',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              GlassTextField(
                controller: _password,
                placeholder: 'Test account password',
                obscureText: true,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _runPasswordFirst,
                    icon: const Icon(Icons.login),
                    label: const Text('Password-first login'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _checkHealth,
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Health + LAN prompt'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _startDeviceLogin,
                    icon: const Icon(Icons.phone_iphone),
                    label: const Text('Device login (Safari)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pollTimer == null ? null : _stopDeviceLogin,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop polling'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer.card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Log (redacted)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _log.isEmpty ? null : _copyLog,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 260,
                child: _log.isEmpty
                    ? const Center(child: Text('No requests yet.'))
                    : ListView.builder(
                        itemCount: _log.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _log[index],
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _glassTab() {
    final highContrast = MediaQuery.highContrastOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        GlassContainer.card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Liquid Glass',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'This card, the tab bar, and the sheet use '
                'liquid_glass_widgets 1.17.0.',
              ),
              const SizedBox(height: 16),
              GlassButton(
                icon: const Icon(Icons.open_in_new),
                label: 'Open glass sheet',
                width: 220,
                onTap: _openSheet,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer.card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Force solid fallback'),
                subtitle: const Text(
                  'GlassAccessibilityScope reduceTransparency: true',
                ),
                value: widget.forceSolid,
                onChanged: widget.onForceSolidChanged,
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Performance overlay'),
                subtitle: const Text('Show frame timing while you test'),
                value: widget.showPerformanceOverlay,
                onChanged: widget.onPerformanceOverlayChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer.card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'System signals',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text('MediaQuery.highContrast: $highContrast'),
              Text('MediaQuery.disableAnimations: $reduceMotion'),
              const SizedBox(height: 8),
              const Text(
                'The package maps Reduce Transparency to Increase Contrast. '
                'Record both settings on the device.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChecksTab extends StatefulWidget {
  const _ChecksTab();

  @override
  State<_ChecksTab> createState() => _ChecksTabState();
}

class _ChecksTabState extends State<_ChecksTab> {
  final Set<int> _done = <int>{};

  static const List<String> _items = <String>[
    'App launches. The glass tab bar shows three tabs; the gradient is visible through it.',
    'Health + LAN prompt: enter a LAN address, tap Health, allow the Local Network prompt, expect 200.',
    'Password-first: sign-in 200, mint 201, key shape shown, /cli-auth/me 200, sign-out 200.',
    'Device login: challenge 201, Safari opens the approval page, approve, poll approved, /cli-auth/me 200.',
    'Glass sheet: open it from the Glass tab. The panel is readable and the backdrop blurs.',
    'Reduce Transparency: iOS Settings > Accessibility > Display & Text Size > Reduce Transparency. Record glass vs solid.',
    'Increase Contrast: same menu. Expect the solid fallback. Record.',
    'Profile: ./tool/run_ios.sh --profile, enable the performance overlay, switch tabs, open the sheet. Record frame times.',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        GlassContainer.card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'iPhone checks',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Do these in order. Copy the redacted log and paste it with '
                'the results.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer.card(
          child: Column(
            children: [
              for (var index = 0; index < _items.length; index++)
                CheckboxListTile(
                  value: _done.contains(index),
                  onChanged: (value) {
                    setState(() {
                      if (value ?? false) {
                        _done.add(index);
                      } else {
                        _done.remove(index);
                      }
                    });
                  },
                  title: Text(_items[index]),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer.card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Android',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Frame times are not tested. No Android device is available. '
                'Do not use an emulator for the 60 fps gate.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
