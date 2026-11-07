import 'package:flutter/material.dart';
import 'package:paperplane/ui/ui.dart';

/// Root widget of Paperplane.
///
/// This is a placeholder shell. Navigation, auth and features arrive in
/// later PRs.
class PaperplaneApp extends StatefulWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  State<PaperplaneApp> createState() => _PaperplaneAppState();
}

class _PaperplaneAppState extends State<PaperplaneApp> {
  int _tab = 0;

  static const _destinations = [
    AppTabDestination(icon: Icons.inbox_outlined, label: 'Inbox'),
    AppTabDestination(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paperplane',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: Scaffold(
        body: Center(child: Text(_destinations[_tab].label)),
        bottomNavigationBar: AppTabBar(
          destinations: _destinations,
          currentIndex: _tab,
          onSelected: (index) => setState(() => _tab = index),
        ),
      ),
    );
  }
}
